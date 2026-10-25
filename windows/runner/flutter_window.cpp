#include "flutter_window.h"

#include <dwmapi.h>

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <cstddef>
#include <cwchar>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

namespace {

// Shell_NotifyIcon callback and the deferred self-destroy request.
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kDeferredQuitMessage = WM_APP + 3;
constexpr UINT kTrayIconId = 1;
constexpr UINT_PTR kQuitFallbackTimer = 0xC0F1;
constexpr UINT kQuitFallbackMs = 5000;

constexpr UINT kMenuShow = 1;
constexpr UINT kMenuHide = 2;
constexpr UINT kMenuQuit = 4;

constexpr wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValueName[] = L"CloudflareTunnelManager";
constexpr wchar_t kDefaultTrayTip[] = L"Cloudflare Tunnel Manager";

void ApplyTitleBarTheme(HWND window, bool dark) {
  BOOL immersive_dark = dark ? TRUE : FALSE;
  ::DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &immersive_dark, sizeof(immersive_dark));

  // Windows 11 supports explicit caption colors, which keeps the native title
  // bar aligned with the app palette in both light and dark mode.
  COLORREF caption = dark ? RGB(11, 15, 21) : RGB(250, 251, 253);
  ::DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption,
                          sizeof(caption));
  COLORREF text = dark ? RGB(233, 238, 247) : RGB(16, 23, 37);
  ::DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &text, sizeof(text));
  COLORREF border = dark ? RGB(28, 34, 43) : RGB(226, 230, 236);
  ::DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border, sizeof(border));

  ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  ::RedrawWindow(window, nullptr, nullptr, RDW_FRAME | RDW_INVALIDATE);
}

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        wide.data(), length);
  return wide;
}

void CopyToWideBuffer(wchar_t* buffer, size_t capacity, const wchar_t* source) {
  if (buffer == nullptr || capacity == 0) {
    return;
  }
  wcsncpy_s(buffer, capacity, source, _TRUNCATE);
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  for (size_t attempt = 0; attempt < 4; ++attempt) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (length < buffer.size()) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2);
  }
  return std::wstring();
}

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "cf_tunnel/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "setTitleBarDark") {
          const auto* dark = std::get_if<bool>(call.arguments());
          if (dark != nullptr) {
            ApplyTitleBarTheme(GetHandle(), *dark);
          }
          result->Success();
        } else if (method == "hideToTray") {
          HideToTray();
          result->Success();
        } else if (method == "quit") {
          // Destroy on the next loop turn: this callback is dispatched by the
          // Flutter engine, so it must not tear the engine down while running.
          ::KillTimer(GetHandle(), kQuitFallbackTimer);
          force_quit_ = true;
          result->Success();
          ::PostMessage(GetHandle(), kDeferredQuitMessage, 0, 0);
        } else if (method == "setCloseToTray") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled != nullptr) {
            close_to_tray_ = *enabled;
          }
          result->Success();
        } else if (method == "setTooltip") {
          const auto* tip = std::get_if<std::string>(call.arguments());
          if (tip != nullptr) {
            SetTrayTooltip(*tip);
          }
          result->Success();
        } else if (method == "setAutoStart") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          const bool ok = enabled != nullptr && WriteAutoStart(*enabled);
          result->Success(flutter::EncodableValue(ok));
        } else if (method == "isAutoStartEnabled") {
          result->Success(flutter::EncodableValue(IsAutoStartRegistered()));
        } else {
          result->NotImplemented();
        }
      });

  InstallTrayIcon();
  // A boot start stays headless: no window, no first-run balloon.
  hidden_in_tray_ = start_hidden_;
  balloon_shown_ = start_hidden_;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Tray, lifecycle and the window's own close button are handled here before
  // Flutter sees them, so the window can hide instead of being destroyed.
  switch (message) {
    case kTrayCallbackMessage:
      HandleTrayClick(wparam, lparam);
      return 0;

    case cf_window::kShowFromSecondInstance:
      ShowFromTray();
      return 0;

    case kDeferredQuitMessage:
      force_quit_ = true;
      RemoveTrayIcon();
      Destroy();
      return 0;

    case WM_TIMER:
      if (wparam == kQuitFallbackTimer) {
        // Dart never answered the quit request; stop waiting and close.
        ::KillTimer(hwnd, kQuitFallbackTimer);
        ::PostMessage(hwnd, kDeferredQuitMessage, 0, 0);
        return 0;
      }
      break;

    case WM_CLOSE:
      if (!force_quit_ && close_to_tray_) {
        HideToTray();
        return 0;
      }
      break;

    case WM_QUERYENDSESSION:
      // A logoff or shutdown is not a "hide me" request; let the window die.
      force_quit_ = true;
      break;

    default:
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == WM_FONTCHANGE) {
    flutter_controller_->engine()->ReloadSystemFonts();
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::InstallTrayIcon() {
  if (tray_installed_) {
    return;
  }
  tray_data_ = {};
  tray_data_.cbSize = sizeof(tray_data_);
  tray_data_.hWnd = GetHandle();
  tray_data_.uID = kTrayIconId;
  tray_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_data_.hIcon =
      ::LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  if (tray_data_.hIcon == nullptr) {
    tray_data_.hIcon = ::LoadIconW(nullptr, IDI_APPLICATION);
  }
  CopyToWideBuffer(tray_data_.szTip, ARRAYSIZE(tray_data_.szTip),
                   kDefaultTrayTip);
  tray_installed_ = ::Shell_NotifyIconW(NIM_ADD, &tray_data_) != FALSE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_installed_) {
    return;
  }
  tray_installed_ = false;
  ::Shell_NotifyIconW(NIM_DELETE, &tray_data_);
}

void FlutterWindow::SetTrayTooltip(const std::string& utf8_text) {
  if (!tray_installed_) {
    return;
  }
  const std::wstring tip = Utf16FromUtf8(utf8_text);
  CopyToWideBuffer(tray_data_.szTip, ARRAYSIZE(tray_data_.szTip),
                   tip.empty() ? kDefaultTrayTip : tip.c_str());
  tray_data_.uFlags = NIF_TIP;
  ::Shell_NotifyIconW(NIM_MODIFY, &tray_data_);
}

void FlutterWindow::HandleTrayClick(WPARAM wparam, LPARAM lparam) {
  (void)wparam;
  switch (static_cast<UINT>(LOWORD(lparam))) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      ShowFromTray();
      break;
    case WM_RBUTTONUP:
    case WM_NCRBUTTONUP:
    case WM_CONTEXTMENU:
      ShowTrayMenu();
      break;
    default:
      break;
  }
}

void FlutterWindow::ShowTrayMenu() {
  if (!IsWindow(GetHandle())) {
    return;
  }
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kMenuShow, L"显示主界面");
  ::AppendMenuW(menu, MF_STRING, kMenuHide, L"隐藏主界面");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, L"退出并停止隧道");
  ::EnableMenuItem(menu, kMenuShow, hidden_in_tray_ ? MF_ENABLED : MF_GRAYED);
  ::EnableMenuItem(menu, kMenuHide, hidden_in_tray_ ? MF_GRAYED : MF_ENABLED);

  POINT cursor = {};
  ::GetCursorPos(&cursor);
  // Required so the popup closes again when the click outside it arrives.
  ::SetForegroundWindow(GetHandle());
  const int choice = ::TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, cursor.x, cursor.y,
      0, GetHandle(), nullptr);
  ::DestroyMenu(menu);
  ::PostMessage(GetHandle(), WM_NULL, 0, 0);

  // The shell may queue WM_CONTEXTMENU for the same right click; drain it so a
  // second menu does not pop up right after the first one closes.
  MSG pending = {};
  while (::PeekMessageW(&pending, GetHandle(), WM_CONTEXTMENU, WM_CONTEXTMENU,
                        PM_REMOVE)) {
  }

  switch (choice) {
    case kMenuShow:
      ShowFromTray();
      break;
    case kMenuHide:
      HideToTray();
      break;
    case kMenuQuit:
      RequestQuit();
      break;
    default:
      break;
  }
}

void FlutterWindow::ShowFromTray() {
  if (!IsWindow(GetHandle())) {
    return;
  }
  ::ShowWindow(GetHandle(), SW_SHOWNORMAL);
  ::SetWindowPos(GetHandle(), HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  ::SetForegroundWindow(GetHandle());
  ::RedrawWindow(GetHandle(), nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW);
  hidden_in_tray_ = false;
}

void FlutterWindow::HideToTray() {
  if (!IsWindow(GetHandle())) {
    return;
  }
  ::ShowWindow(GetHandle(), SW_HIDE);
  hidden_in_tray_ = true;

  if (tray_installed_ && !balloon_shown_) {
    balloon_shown_ = true;
    tray_data_.uFlags = NIF_INFO;
    CopyToWideBuffer(tray_data_.szInfoTitle, ARRAYSIZE(tray_data_.szInfoTitle),
                     L"已在后台运行");
    CopyToWideBuffer(tray_data_.szInfo, ARRAYSIZE(tray_data_.szInfo),
                     L"隧道继续运行，双击托盘图标可重新打开窗口。");
    tray_data_.dwInfoFlags = NIIF_INFO;
    ::Shell_NotifyIconW(NIM_MODIFY, &tray_data_);
    tray_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  }
}

void FlutterWindow::RequestQuit() {
  force_quit_ = true;
  if (window_channel_) {
    // Dart stops the tunnels and calls back into "quit"; the timer is the
    // safety net when the isolate is gone or wedged.
    window_channel_->InvokeMethod("requestQuit", nullptr);
    ::SetTimer(GetHandle(), kQuitFallbackTimer, kQuitFallbackMs, nullptr);
  }
}

bool FlutterWindow::WriteAutoStart(bool enabled) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0,
                      KEY_SET_VALUE | KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return false;
  }

  bool ok = false;
  if (enabled) {
    const std::wstring executable = ExecutablePath();
    if (!executable.empty()) {
      const std::wstring command = L"\"" + executable + L"\" --autostart";
      const DWORD bytes =
          static_cast<DWORD>((command.length() + 1) * sizeof(wchar_t));
      ok = ::RegSetValueExW(key, kRunValueName, 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(command.c_str()),
                            bytes) == ERROR_SUCCESS;
    }
  } else {
    const LSTATUS removed = ::RegDeleteValueW(key, kRunValueName);
    ok = removed == ERROR_SUCCESS || removed == ERROR_FILE_NOT_FOUND;
  }

  ::RegCloseKey(key);
  return ok;
}

bool FlutterWindow::IsAutoStartRegistered() {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t buffer[MAX_PATH * 4] = {};
  DWORD bytes = sizeof(buffer);
  const LSTATUS status = ::RegGetValueW(key, nullptr, kRunValueName,
                                        RRF_RT_REG_SZ, nullptr, buffer, &bytes);
  ::RegCloseKey(key);
  if (status != ERROR_SUCCESS) {
    return false;
  }
  const std::wstring executable = ExecutablePath();
  if (executable.empty()) {
    return false;
  }
  return std::wstring(buffer).find(executable) != std::wstring::npos;
}
