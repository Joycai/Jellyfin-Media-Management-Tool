#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "thumbnail_channel.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // True once window_manager has removed the standard caption, which is when
  // the app draws its own 46x48 buttons and this window may claim
  // HTMAXBUTTON for the middle one.
  bool HasCustomTitleBar(HWND hwnd) const;

  // Screen-coordinate rectangle of the maximize button, in step with what
  // Flutter draws (including the inset a maximized window needs).
  RECT MaximizeButtonRect(HWND hwnd) const;

  // Pushes hover / pressed state for the maximize button back to Dart.
  // Windows routes input over an HTMAXBUTTON rectangle as non-client, so
  // Flutter cannot observe it on its own.
  void SendCaptionState(const char* method, bool value);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      caption_channel_;

  // Video poster frames, extracted on worker threads. See thumbnail_channel.h
  // for why this is not left to the plugin on Windows.
  std::unique_ptr<ThumbnailChannel> thumbnail_channel_;

  bool maximize_hovered_ = false;
  bool maximize_pressed_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
