#include <windows.h>

#include <filesystem>
#include <string>
#include <vector>

namespace {
std::wstring quote(const std::filesystem::path& value) {
    return L"\"" + value.wstring() + L"\"";
}
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR arguments, int) {
    std::vector<wchar_t> modulePath(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, modulePath.data(), static_cast<DWORD>(modulePath.size()));
    if (length == 0 || length == modulePath.size()) {
        MessageBoxW(nullptr, L"Could not resolve the OpenDAO installation directory.", L"OpenDAO", MB_ICONERROR);
        return 2;
    }

    const auto root = std::filesystem::path(std::wstring(modulePath.data(), length)).parent_path();
    const auto engine = root / L"OpenDAO-engine.exe";
    const auto pack = root / L"OpenDAO.pck";
    if (!std::filesystem::exists(engine) || !std::filesystem::exists(pack)) {
        MessageBoxW(nullptr, L"OpenDAO-engine.exe or OpenDAO.pck is missing. Re-extract the release archive.", L"OpenDAO", MB_ICONERROR);
        return 3;
    }

    std::wstring command = quote(engine) + L" --xr-mode off --main-pack " + quote(pack);
    if (arguments != nullptr && arguments[0] != L'\0') {
        command += L" ";
        command += arguments;
    }
    std::vector<wchar_t> mutableCommand(command.begin(), command.end());
    mutableCommand.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    const BOOL created = CreateProcessW(
        engine.c_str(), mutableCommand.data(), nullptr, nullptr, FALSE, 0, nullptr, root.c_str(), &startup, &process);
    if (!created) {
        MessageBoxW(nullptr, L"The bundled OpenDAO rendering engine could not be started.", L"OpenDAO", MB_ICONERROR);
        return 4;
    }

    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exitCode = 1;
    GetExitCodeProcess(process.hProcess, &exitCode);
    CloseHandle(process.hProcess);
    return static_cast<int>(exitCode);
}
