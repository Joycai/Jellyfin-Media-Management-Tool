#include "flutter_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <optional>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Design spec 2.2: the caption buttons are 46 x 48 logical pixels, flush to
// the top-right corner, and the maximize button is the middle of the three.
constexpr int kCaptionButtonWidth = 46;
constexpr int kCaptionButtonHeight = 48;

// Windows overflows a maximized window past the screen edge by the frame
// thickness. Flutter adds the same inset back (see AppShell), so the native
// hit rectangle has to move with it or it lands 8px off the drawn button.
constexpr int kMaximizedInset = 8;

constexpr char kCaptionChannel[] = "jellyfin/window_caption";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  caption_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kCaptionChannel,
          &flutter::StandardMethodCodec::GetInstance());

  thumbnail_channel_ = std::make_unique<ThumbnailChannel>(
      flutter_controller_->engine()->messenger(), GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Both channels go before the controller: their destructors answer whatever
  // is still outstanding, and that needs a live engine.
  thumbnail_channel_ = nullptr;
  caption_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::HasCustomTitleBar(HWND hwnd) const {
  // Only hijack the hit test once window_manager has actually taken the
  // caption away. During startup the standard title bar is still up, and
  // claiming HTMAXBUTTON over it would fight the real button.
  return (GetWindowLongPtr(hwnd, GWL_STYLE) & WS_CAPTION) == 0;
}

RECT FlutterWindow::MaximizeButtonRect(HWND hwnd) const {
  RECT window{};
  GetWindowRect(hwnd, &window);
  const double scale = GetDpiForWindow(hwnd) / 96.0;
  const LONG button_w = static_cast<LONG>(kCaptionButtonWidth * scale);
  const LONG button_h = static_cast<LONG>(kCaptionButtonHeight * scale);
  const LONG inset =
      IsZoomed(hwnd) ? static_cast<LONG>(kMaximizedInset * scale) : 0;

  const LONG right = window.right - inset - button_w;  // close button's left
  RECT rect{};
  rect.right = right;
  rect.left = right - button_w;
  rect.top = window.top + inset;
  rect.bottom = rect.top + button_h;
  return rect;
}

void FlutterWindow::SendCaptionState(const char* method, bool value) {
  if (!caption_channel_) return;
  caption_channel_->InvokeMethod(
      method, std::make_unique<flutter::EncodableValue>(value));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  // Not a switch case: the value is registered at runtime, so it is not a
  // compile-time constant.
  if (thumbnail_channel_ != nullptr &&
      message == ThumbnailChannel::CompletionMessage()) {
    thumbnail_channel_->DrainCompletions();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    // Snap Layouts. Hovering the maximize button for ~400ms pops up Windows'
    // own snap flyout, but ONLY if that button reports HTMAXBUTTON from
    // WM_NCHITTEST and its hit area is at least 46x32 — which is exactly why
    // the design pins the caption buttons to 46x48 and forbids anything else
    // in the top-right 138px.
    //
    // The cost of claiming HTMAXBUTTON is that Windows then routes mouse
    // input over that rectangle as *non-client*: Flutter never sees a hover
    // or a click there. So this handler owns both — it forwards the hover and
    // pressed state to Dart so the button still lights up, and performs the
    // maximize itself.
    case WM_NCHITTEST: {
      if (!HasCustomTitleBar(hwnd)) break;
      const LRESULT hit =
          DefWindowProc(hwnd, message, wparam, lparam);
      // Only upgrade a plain client hit; the resize borders DefWindowProc
      // reports must keep winning, or the window stops being resizable along
      // its top edge.
      if (hit != HTCLIENT) break;
      const POINT cursor{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const RECT button = MaximizeButtonRect(hwnd);
      if (PtInRect(&button, cursor)) return HTMAXBUTTON;
      break;
    }

    case WM_NCMOUSEMOVE: {
      if (wparam != HTMAXBUTTON) break;
      if (!maximize_hovered_) {
        maximize_hovered_ = true;
        SendCaptionState("maximizeHover", true);
        // Without this there is no WM_NCMOUSELEAVE and the button would stay
        // lit after the pointer moves away.
        TRACKMOUSEEVENT track{sizeof(TRACKMOUSEEVENT), TME_LEAVE | TME_NONCLIENT,
                              hwnd, 0};
        TrackMouseEvent(&track);
      }
      return 0;
    }

    case WM_NCMOUSELEAVE: {
      if (!maximize_hovered_ && !maximize_pressed_) break;
      maximize_hovered_ = false;
      maximize_pressed_ = false;
      SendCaptionState("maximizePressed", false);
      SendCaptionState("maximizeHover", false);
      return 0;
    }

    case WM_NCLBUTTONDOWN: {
      if (wparam != HTMAXBUTTON) break;
      maximize_pressed_ = true;
      SendCaptionState("maximizePressed", true);
      // Swallow it: letting DefWindowProc have this enters the modal
      // move/size loop and paints the legacy button frame.
      return 0;
    }

    case WM_NCLBUTTONUP: {
      if (wparam != HTMAXBUTTON) break;
      const bool was_pressed = maximize_pressed_;
      maximize_pressed_ = false;
      SendCaptionState("maximizePressed", false);
      if (was_pressed) {
        ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
      }
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
