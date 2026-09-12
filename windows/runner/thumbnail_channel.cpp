#include "thumbnail_channel.h"

#include <objbase.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <flutter/standard_method_codec.h>

#include <thread>
#include <utility>

namespace {

using Microsoft::WRL::ComPtr;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kChannelName[] = "jellyfin/thumbnail";

// Matches ThumbnailService._maxConcurrent on the Dart side. Three is enough
// to keep a fast scroll fed without asking a NAS for a dozen files at once.
constexpr int kWorkerCount = 3;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring utf16(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), utf16.data(), length);
  return utf16;
}

// Encodes a Shell thumbnail bitmap as JPEG. JPEG rather than PNG because the
// Dart cache writes these straight to `<key>.jpg` and a poster frame has no
// alpha to preserve.
bool EncodeJpeg(HBITMAP bitmap, int quality, std::vector<uint8_t>* out) {
  ComPtr<IWICImagingFactory> wic;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)))) {
    return false;
  }

  ComPtr<IWICBitmap> source;
  // The Shell returns a 32bpp DIB whose alpha channel is uninitialised for an
  // opaque frame. WICBitmapIgnoreAlpha stops that garbage from being read as
  // transparency, which otherwise yields a black or half-erased image.
  if (FAILED(wic->CreateBitmapFromHBITMAP(bitmap, nullptr, WICBitmapIgnoreAlpha,
                                          &source))) {
    return false;
  }

  ComPtr<IStream> stream;
  if (FAILED(::CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return false;

  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(wic->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &encoder))) {
    return false;
  }
  if (FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return false;
  }

  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> options;
  if (FAILED(encoder->CreateNewFrame(&frame, &options))) return false;

  PROPBAG2 option = {};
  option.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
  VARIANT value = {};
  value.vt = VT_R4;
  value.fltVal = static_cast<float>(quality) / 100.0f;
  options->Write(1, &option, &value);

  if (FAILED(frame->Initialize(options.Get()))) return false;
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  if (FAILED(frame->SetPixelFormat(&format))) return false;
  if (FAILED(frame->WriteSource(source.Get(), nullptr))) return false;
  if (FAILED(frame->Commit())) return false;
  if (FAILED(encoder->Commit())) return false;

  // Read the exact written length back off the stream. GlobalSize() on the
  // underlying handle reports the *allocated* block, which is rounded up and
  // would append trailing garbage to every file.
  const LARGE_INTEGER zero = {};
  ULARGE_INTEGER end = {};
  if (FAILED(stream->Seek(zero, STREAM_SEEK_END, &end))) return false;
  if (FAILED(stream->Seek(zero, STREAM_SEEK_SET, nullptr))) return false;
  const size_t length = static_cast<size_t>(end.QuadPart);
  if (length == 0) return false;

  out->resize(length);
  ULONG read = 0;
  if (FAILED(stream->Read(out->data(), static_cast<ULONG>(length), &read)) ||
      read != length) {
    out->clear();
    return false;
  }
  return true;
}

bool Extract(const std::wstring& path, int edge, int quality,
             std::vector<uint8_t>* out) {
  ComPtr<IShellItem> item;
  if (FAILED(::SHCreateItemFromParsingName(path.c_str(), nullptr,
                                           IID_PPV_ARGS(&item)))) {
    return false;
  }
  ComPtr<IShellItemImageFactory> factory;
  if (FAILED(item.As(&factory))) return false;

  HBITMAP bitmap = nullptr;
  const SIZE size = {edge, edge};
  // SIIGBF_THUMBNAILONLY: never fall back to the file-type icon. Dart already
  // draws its own icon for "no thumbnail", and a 32px Shell icon blown up to
  // 320 looks like a corrupt poster frame rather than a missing one.
  //
  // No SIIGBF_BIGGERSIZEOK. It sounds free -- take whatever size the provider
  // already has instead of making it resample -- but what the provider has is
  // whatever Explorer cached, which is routinely 1280x720. That went into the
  // JPEG at 138 KB a row against the plugin's ~16 KB, i.e. an 8x heavier disk
  // cache and a 240-entry memory LRU eight times the size, to fill a 34pt row.
  const HRESULT hr =
      factory->GetImage(size, SIIGBF_THUMBNAILONLY, &bitmap);
  if (FAILED(hr) || bitmap == nullptr) return false;

  const bool ok = EncodeJpeg(bitmap, quality, out);
  ::DeleteObject(bitmap);
  return ok;
}

}  // namespace

UINT ThumbnailChannel::CompletionMessage() {
  // Registered once per process; the value is unique system-wide, so no
  // plugin sharing this HWND can mistake it for one of its own.
  static const UINT message =
      ::RegisterWindowMessageW(L"JellyfinThumbnailExtractionDone");
  return message;
}

void ThumbnailChannel::RunWorker(std::shared_ptr<Shared> shared) {
  // Shell thumbnail providers are apartment-threaded COM objects. Without a
  // per-thread STA every CoCreateInstance here fails with CO_E_NOTINITIALIZED
  // and no thumbnail is ever produced — silently, since every failure path
  // degrades to "no thumbnail".
  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  for (;;) {
    Job job;
    {
      std::unique_lock<std::mutex> lock(shared->mutex);
      shared->wake.wait(lock,
                        [&] { return shared->stop || !shared->queue.empty(); });
      if (shared->stop) break;
      job = std::move(shared->queue.front());
      shared->queue.pop_front();
    }

    std::vector<uint8_t> jpeg;
    if (!Extract(job.path, job.edge, job.quality, &jpeg)) jpeg.clear();

    HWND host = nullptr;
    UINT message = 0;
    {
      std::lock_guard<std::mutex> lock(shared->mutex);
      // The window is gone; there is nobody left to answer.
      if (shared->stop) break;
      shared->done.push_back({job.id, std::move(jpeg)});
      host = shared->host;
      message = shared->message;
    }
    if (host != nullptr) ::PostMessageW(host, message, 0, 0);
  }

  if (SUCCEEDED(com)) ::CoUninitialize();
}

ThumbnailChannel::ThumbnailChannel(flutter::BinaryMessenger* messenger,
                                   HWND host)
    : shared_(std::make_shared<Shared>()) {
  shared_->host = host;
  shared_->message = CompletionMessage();

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleCall(call, std::move(result));
      });

  // Detached rather than joined. A worker can be parked inside a Shell call
  // reading video over SMB for many seconds, and joining that on the way out
  // would hang the window close; the shared_ptr is what keeps the state it
  // touches alive instead.
  for (int i = 0; i < kWorkerCount; ++i) {
    std::thread(&ThumbnailChannel::RunWorker, shared_).detach();
  }
}

ThumbnailChannel::~ThumbnailChannel() {
  {
    std::lock_guard<std::mutex> lock(shared_->mutex);
    shared_->stop = true;
    shared_->queue.clear();
    shared_->host = nullptr;
  }
  shared_->wake.notify_all();

  // The engine is still up at this point (FlutterWindow tears the channel down
  // before the controller), so answer everything still outstanding rather than
  // dropping replies on the floor.
  for (auto& entry : pending_) entry.second->Success();
  pending_.clear();
}

void ThumbnailChannel::DrainCompletions() {
  std::deque<Completion> done;
  {
    std::lock_guard<std::mutex> lock(shared_->mutex);
    done.swap(shared_->done);
  }
  for (auto& completion : done) {
    const auto it = pending_.find(completion.id);
    if (it == pending_.end()) continue;
    if (completion.jpeg.empty()) {
      it->second->Success();
    } else {
      it->second->Success(EncodableValue(std::move(completion.jpeg)));
    }
    pending_.erase(it);
  }
}

void ThumbnailChannel::HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() != "extract") {
    result->NotImplemented();
    return;
  }

  const auto* arguments = std::get_if<EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    result->Error("bad_args", "extract expects a map");
    return;
  }

  auto lookup = [arguments](const char* key) -> const EncodableValue* {
    const auto it = arguments->find(EncodableValue(key));
    return it == arguments->end() ? nullptr : &it->second;
  };

  const auto* path = lookup("path");
  const auto* edge = lookup("edge");
  const auto* quality = lookup("quality");
  if (path == nullptr || !std::holds_alternative<std::string>(*path) ||
      edge == nullptr || !std::holds_alternative<int32_t>(*edge) ||
      quality == nullptr || !std::holds_alternative<int32_t>(*quality)) {
    result->Error("bad_args", "extract expects path, edge and quality");
    return;
  }

  const std::wstring wide = Utf16FromUtf8(std::get<std::string>(*path));
  if (wide.empty()) {
    result->Success();
    return;
  }

  const uint64_t id = next_id_++;
  pending_[id] = std::move(result);
  {
    std::lock_guard<std::mutex> lock(shared_->mutex);
    shared_->queue.push_back(
        {id, wide, std::get<int32_t>(*edge), std::get<int32_t>(*quality)});
  }
  shared_->wake.notify_one();
}
