#ifndef RUNNER_THUMBNAIL_CHANNEL_H_
#define RUNNER_THUMBNAIL_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Video poster frames for the file table, extracted off the platform thread.
//
// This exists because `fc_native_video_thumbnail` 3.0.1 has no threading at
// all on Windows: its `HandleMethodCall` runs `IThumbnailCache::GetThumbnail`
// synchronously and replies inline. That call is a blocking Windows Shell
// extraction, and for a file on a NAS it reads video over SMB — on the
// Flutter platform thread, which is the thread pumping the window's message
// loop. Entering a folder of network videos measured 21ms -> 46.6ms per frame
// for exactly that reason. The Dart-side concurrency gate could not help: all
// three "parallel" requests serialised behind the same thread.
//
// So Windows gets its own channel and a small worker pool. The plugin stays
// in place for macOS and Linux, whose backends already thread.
//
// The reply path is the part worth reading twice. A `flutter::MethodResult`
// may only be completed on the platform thread, so a worker never touches it:
// it parks the encoded bytes on a shared queue and posts a window message,
// and the platform thread drains the queue from the window procedure.
class ThumbnailChannel {
 public:
  // |host| receives CompletionMessage() whenever results are ready. It must
  // outlive this object, which the runner guarantees: FlutterWindow destroys
  // the channel in OnDestroy, before the HWND goes away.
  ThumbnailChannel(flutter::BinaryMessenger* messenger, HWND host);
  ~ThumbnailChannel();

  ThumbnailChannel(const ThumbnailChannel&) = delete;
  ThumbnailChannel& operator=(const ThumbnailChannel&) = delete;

  // The window message workers post to wake the platform thread. Registered
  // rather than WM_APP+n so it cannot collide with a plugin using the same
  // HWND for its own notifications.
  static UINT CompletionMessage();

  // Answers every request whose extraction has finished. Platform thread only.
  void DrainCompletions();

 private:
  struct Job {
    uint64_t id;
    std::wstring path;
    int edge;
    int quality;
  };

  struct Completion {
    uint64_t id;
    std::vector<uint8_t> jpeg;  // empty = no thumbnail could be produced
  };

  // Everything the detached workers touch. Held by shared_ptr so a worker
  // still blocked in a Shell call when the window closes has something valid
  // to come back to.
  struct Shared {
    std::mutex mutex;
    std::condition_variable wake;
    std::deque<Job> queue;
    std::deque<Completion> done;
    bool stop = false;
    HWND host = nullptr;
    UINT message = 0;
  };

  // Body of each pool thread. Static, and takes the state by shared_ptr, so a
  // worker blocked in a Shell call outlives the ThumbnailChannel safely.
  static void RunWorker(std::shared_ptr<Shared> shared);

  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<Shared> shared_;

  // Platform thread only, so it needs no lock.
  std::map<uint64_t,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      pending_;
  uint64_t next_id_ = 1;
};

#endif  // RUNNER_THUMBNAIL_CHANNEL_H_
