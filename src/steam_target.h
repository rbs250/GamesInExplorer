#pragma once
#include <string>
#include <algorithm>

enum class SteamTargetAction { None, Play, Install };

inline SteamTargetAction ClassifySteamTarget(const std::wstring& id, const std::wstring& target) {
    if (id.size() <= 6 || id.size() > 80 || id.rfind(L"steam-", 0) != 0 ||
        !std::all_of(id.begin() + 6, id.end(), [](wchar_t c) { return c >= L'0' && c <= L'9'; }))
        return SteamTargetAction::None;
    const auto app = id.substr(6);
    if (target == L"steam://rungameid/" + app) return SteamTargetAction::Play;
    if (target == L"steam://install/" + app) return SteamTargetAction::Install;
    return SteamTargetAction::None;
}
