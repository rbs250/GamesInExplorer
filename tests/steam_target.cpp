#include "../src/steam_target.h"
#include <cstdio>

int main() {
    struct Case { const wchar_t* id; const wchar_t* target; SteamTargetAction expected; };
    const Case cases[] = {
        {L"steam-2525380", L"steam://rungameid/2525380", SteamTargetAction::Play},
        {L"steam-2525380", L"steam://install/2525380", SteamTargetAction::Install},
        {L"steam-2525380", L"steam://install/1091500", SteamTargetAction::None},
        {L"steam-2525380", L"steam://rungameid/1091500", SteamTargetAction::None},
        {L"steam-2525380", L"steam://uninstall/2525380", SteamTargetAction::None},
        {L"steam-2525380", L"https://example.com/2525380", SteamTargetAction::None},
        {L"steam-2525380", L"steam://install/2525380?extra=1", SteamTargetAction::None},
        {L"steam-2525380", L"steam://install/2525380\r\n", SteamTargetAction::None},
        {L"steam-2525380", L"steam://install/25253800", SteamTargetAction::None},
        {L"steam-", L"steam://install/", SteamTargetAction::None},
        {L"steam-1/../../x", L"steam://install/1/../../x", SteamTargetAction::None},
        {L"local-0000000000000000", L"steam://install/0000000000000000", SteamTargetAction::None},
        {L"steam-2525380", L"", SteamTargetAction::None}
    };
    int failures = 0;
    for (const auto& test : cases) {
        if (ClassifySteamTarget(test.id, test.target) != test.expected) {
            std::wprintf(L"FAIL: %ls -> %ls\n", test.id, test.target);
            ++failures;
        }
    }
    if (!failures) std::puts("PASS: 13 Steam play/install target checks; wrong IDs and unexpected protocols rejected.");
    return failures ? 1 : 0;
}
