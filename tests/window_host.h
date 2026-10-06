#pragma once
#include "../src/common.h"
class TestBrowser final : public IShellBrowser {
    long refs=1; HWND window;
public:
    explicit TestBrowser(HWND owner):window(owner){}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override{if(!out)return E_POINTER;*out=nullptr;if(id==IID_IUnknown||id==IID_IOleWindow||id==IID_IShellBrowser){*out=static_cast<IShellBrowser*>(this);AddRef();return S_OK;}return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef() override{return InterlockedIncrement(&refs);}ULONG STDMETHODCALLTYPE Release() override{auto n=InterlockedDecrement(&refs);if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE GetWindow(HWND* out) override{*out=window;return S_OK;}
    HRESULT STDMETHODCALLTYPE ContextSensitiveHelp(BOOL) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE InsertMenusSB(HMENU,LPOLEMENUGROUPWIDTHS) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE SetMenuSB(HMENU,HOLEMENU,HWND) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE RemoveMenusSB(HMENU) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE SetStatusTextSB(LPCWSTR) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE EnableModelessSB(BOOL) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE TranslateAcceleratorSB(MSG*,WORD) override{return S_FALSE;}
    HRESULT STDMETHODCALLTYPE BrowseObject(PCUIDLIST_RELATIVE,UINT) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetViewStateStream(DWORD,IStream** out) override{*out=nullptr;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetControlWindow(UINT,HWND* out) override{*out=nullptr;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE SendControlMsg(UINT,UINT,WPARAM,LPARAM,LRESULT* out) override{if(out)*out=0;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE QueryActiveShellView(IShellView** out) override{*out=nullptr;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE OnViewWindowActive(IShellView*) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE SetToolbarItems(LPTBBUTTONSB,UINT,UINT) override{return E_NOTIMPL;}
};
inline void PumpFor(DWORD ms){auto end=GetTickCount64()+ms;do{MSG msg{};while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageW(&msg);}Sleep(10);}while(GetTickCount64()<end);}
