#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wrl.h>
#include <string>
#include <memory>
#include "WebView2.h"
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Callback;
inline const CLSID CLSID_Games = {0xb755c58d,0x7cb3,0x4afe,{0xb9,0x01,0x69,0xb3,0xae,0x21,0xf8,0xd4}};
inline constexpr wchar_t GamesGuid[] = L"{B755C58D-7CB3-4AFE-B901-69B3AE21F8D4}";
extern HINSTANCE g_instance;
extern long g_objects;
std::wstring ModuleFolder();
HRESULT CreateGamesView(IShellFolder* folder, REFIID riid, void** result);
inline HRESULT CopyString(const wchar_t* text, STRRET* value) {
    if (!value) return E_POINTER;
    value->uType = STRRET_WSTR;
    return SHStrDupW(text, &value->pOleStr);
}
