#include "common.h"
#include <new>
HINSTANCE g_instance = nullptr;
long g_objects = 0;
std::wstring ModuleFolder() {
    wchar_t path[32768]{}; GetModuleFileNameW(g_instance,path,32768); PathRemoveFileSpecW(path); return path;
}
class EmptyItems final : public IEnumIDList {
    long refs = 1;
public:
    EmptyItems(){InterlockedIncrement(&g_objects);} ~EmptyItems(){InterlockedDecrement(&g_objects);}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override { if(!out)return E_POINTER;*out=nullptr;if(id==IID_IUnknown||id==IID_IEnumIDList){*out=static_cast<IEnumIDList*>(this);AddRef();return S_OK;}return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override{return InterlockedIncrement(&refs);} ULONG STDMETHODCALLTYPE Release() override{auto n=InterlockedDecrement(&refs);if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE Next(ULONG n,PITEMID_CHILD* items,ULONG* fetched) override {if(fetched)*fetched=0;if(items&&n)items[0]=nullptr;return S_FALSE;}
    HRESULT STDMETHODCALLTYPE Skip(ULONG) override{return S_FALSE;}
    HRESULT STDMETHODCALLTYPE Reset() override{return S_OK;}
    HRESULT STDMETHODCALLTYPE Clone(IEnumIDList** out) override{if(!out)return E_POINTER;*out=new(std::nothrow)EmptyItems;return *out?S_OK:E_OUTOFMEMORY;}
};
class GamesFolder final : public IShellFolder2,public IPersistFolder2,public IExplorerPaneVisibility {
    long refs=1; PIDLIST_ABSOLUTE pidl=nullptr;
public:
    GamesFolder(){InterlockedIncrement(&g_objects);} ~GamesFolder(){CoTaskMemFree(pidl);InterlockedDecrement(&g_objects);}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override{
        if(!out)return E_POINTER;*out=nullptr;
        if(id==IID_IUnknown||id==IID_IShellFolder||id==IID_IShellFolder2)*out=static_cast<IShellFolder2*>(this);
        else if(id==IID_IPersist||id==IID_IPersistFolder||id==IID_IPersistFolder2)*out=static_cast<IPersistFolder2*>(this);
        else if(id==IID_IExplorerPaneVisibility)*out=static_cast<IExplorerPaneVisibility*>(this);
        if(!*out)return E_NOINTERFACE;AddRef();return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override{return InterlockedIncrement(&refs);} ULONG STDMETHODCALLTYPE Release() override{auto n=InterlockedDecrement(&refs);if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE GetClassID(CLSID* out) override{if(!out)return E_POINTER;*out=CLSID_Games;return S_OK;}
    HRESULT STDMETHODCALLTYPE GetPaneState(REFEXPLORERPANE pane,EXPLORERPANESTATE* out) override{if(!out)return E_POINTER;*out=(pane==EP_DetailsPane||pane==EP_PreviewPane)?static_cast<EXPLORERPANESTATE>(EPS_DEFAULT_OFF|EPS_FORCE):EPS_DONTCARE;return S_OK;}
    HRESULT STDMETHODCALLTYPE Initialize(PCIDLIST_ABSOLUTE value) override{CoTaskMemFree(pidl);pidl=ILCloneFull(value);return pidl?S_OK:E_OUTOFMEMORY;}
    HRESULT STDMETHODCALLTYPE GetCurFolder(PIDLIST_ABSOLUTE* out) override{if(!out)return E_POINTER;*out=pidl?ILCloneFull(pidl):nullptr;return S_OK;}
    HRESULT STDMETHODCALLTYPE ParseDisplayName(HWND,IBindCtx*,LPWSTR,ULONG* eaten,PIDLIST_RELATIVE* out,ULONG*) override{if(eaten)*eaten=0;if(out)*out=nullptr;return E_INVALIDARG;}
    HRESULT STDMETHODCALLTYPE EnumObjects(HWND,SHCONTF,IEnumIDList** out) override{if(!out)return E_POINTER;*out=new(std::nothrow)EmptyItems;return *out?S_OK:E_OUTOFMEMORY;}
    HRESULT STDMETHODCALLTYPE BindToObject(PCUIDLIST_RELATIVE,IBindCtx*,REFIID,void** out) override{if(out)*out=nullptr;return E_NOINTERFACE;}
    HRESULT STDMETHODCALLTYPE BindToStorage(PCUIDLIST_RELATIVE,IBindCtx*,REFIID,void** out) override{if(out)*out=nullptr;return E_NOINTERFACE;}
    HRESULT STDMETHODCALLTYPE CompareIDs(LPARAM,PCUIDLIST_RELATIVE,PCUIDLIST_RELATIVE) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE CreateViewObject(HWND,REFIID id,void** out) override{return CreateGamesView(this,id,out);}
    HRESULT STDMETHODCALLTYPE GetAttributesOf(UINT,PCUITEMID_CHILD_ARRAY,SFGAOF* flags) override{if(!flags)return E_POINTER;*flags&=SFGAO_FOLDER|SFGAO_BROWSABLE;return S_OK;}
    HRESULT STDMETHODCALLTYPE GetUIObjectOf(HWND,UINT,PCUITEMID_CHILD_ARRAY,REFIID,UINT*,void** out) override{if(out)*out=nullptr;return E_NOINTERFACE;}
    HRESULT STDMETHODCALLTYPE GetDisplayNameOf(PCUITEMID_CHILD,SHGDNF flags,STRRET* out) override{
        return CopyString((flags&SHGDN_FORPARSING)?L"::{B755C58D-7CB3-4AFE-B901-69B3AE21F8D4}":L"Games",out);
    }
    HRESULT STDMETHODCALLTYPE SetNameOf(HWND,PCUITEMID_CHILD,LPCWSTR,SHGDNF,PITEMID_CHILD* out) override{if(out)*out=nullptr;return E_ACCESSDENIED;}
    HRESULT STDMETHODCALLTYPE GetDefaultSearchGUID(GUID* out) override{if(out)*out=GUID_NULL;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE EnumSearches(IEnumExtraSearch** out) override{if(out)*out=nullptr;return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetDefaultColumn(DWORD,ULONG* sort,ULONG* display) override{if(sort)*sort=0;if(display)*display=0;return S_OK;}
    HRESULT STDMETHODCALLTYPE GetDefaultColumnState(UINT,SHCOLSTATEF* out) override{if(out)*out=SHCOLSTATE_TYPE_STR|SHCOLSTATE_ONBYDEFAULT;return S_OK;}
    HRESULT STDMETHODCALLTYPE GetDetailsEx(PCUITEMID_CHILD,const SHCOLUMNID*,VARIANT* out) override{if(out)VariantInit(out);return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetDetailsOf(PCUITEMID_CHILD,UINT column,SHELLDETAILS* out) override{if(!out)return E_POINTER;if(column)return E_INVALIDARG;out->fmt=LVCFMT_LEFT;out->cxChar=30;return CopyString(L"Name",&out->str);}
    HRESULT STDMETHODCALLTYPE MapColumnToSCID(UINT,SHCOLUMNID* out) override{if(out)ZeroMemory(out,sizeof(*out));return E_NOTIMPL;}
};
class Factory final : public IClassFactory {
    long refs=1;
public:
    Factory(){InterlockedIncrement(&g_objects);}~Factory(){InterlockedDecrement(&g_objects);}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override{if(!out)return E_POINTER;*out=nullptr;if(id==IID_IUnknown||id==IID_IClassFactory){*out=static_cast<IClassFactory*>(this);AddRef();return S_OK;}return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef() override{return InterlockedIncrement(&refs);}ULONG STDMETHODCALLTYPE Release() override{auto n=InterlockedDecrement(&refs);if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer,REFIID id,void** out) override{if(!out)return E_POINTER;*out=nullptr;if(outer)return CLASS_E_NOAGGREGATION;auto f=new(std::nothrow)GamesFolder;if(!f)return E_OUTOFMEMORY;auto hr=f->QueryInterface(id,out);f->Release();return hr;}
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override{if(lock)InterlockedIncrement(&g_objects);else InterlockedDecrement(&g_objects);return S_OK;}
};
STDAPI DllGetClassObject(REFCLSID clsid,REFIID id,void** out){if(!out)return E_POINTER;*out=nullptr;if(clsid!=CLSID_Games)return CLASS_E_CLASSNOTAVAILABLE;auto f=new(std::nothrow)Factory;if(!f)return E_OUTOFMEMORY;auto hr=f->QueryInterface(id,out);f->Release();return hr;}
STDAPI DllCanUnloadNow(){if(InterlockedCompareExchange(&g_objects,0,0)!=0)return S_FALSE;if(!UnregisterClassW(L"GamesCoverflowView",g_instance)&&GetLastError()!=ERROR_CLASS_DOES_NOT_EXIST)return S_FALSE;return S_OK;}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH)g_instance=instance;return TRUE;}
