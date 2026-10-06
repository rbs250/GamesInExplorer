#include "../src/common.h"
#include <cstdio>
#include <cassert>
#include "window_host.h"
int wmain(int argc,wchar_t** argv){
    if(argc!=2){wprintf(L"Usage: smoke GamesCoverflow.dll\n");return 2;}
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    if(wcscmp(argv[1],L"--registered")==0){
        ComPtr<IShellFolder> registered;auto hr=CoCreateInstance(CLSID_Games,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&registered));wprintf(L"CoCreateInstance: %08lx\n",hr);
        PIDLIST_ABSOLUTE parsed=nullptr;SFGAOF attributes=SFGAO_FOLDER;hr=SHParseDisplayName(L"::{B755C58D-7CB3-4AFE-B901-69B3AE21F8D4}",nullptr,&parsed,SFGAO_FOLDER,&attributes);wprintf(L"SHParseDisplayName: %08lx; folder attributes: %08lx\n",hr,attributes);
        if(parsed){ComPtr<IShellFolder> bound;hr=SHBindToObject(nullptr,parsed,nullptr,IID_PPV_ARGS(&bound));wprintf(L"SHBindToObject: %08lx\n",hr);CoTaskMemFree(parsed);}return FAILED(hr)?1:0;
    }
    auto dll=LoadLibraryW(argv[1]);if(!dll){wprintf(L"FAIL: extension not loadable (%lu)\n",GetLastError());return 1;}
    auto create=reinterpret_cast<HRESULT(__stdcall*)(REFCLSID,REFIID,void**)>(GetProcAddress(dll,"DllGetClassObject"));
    auto unload=reinterpret_cast<HRESULT(__stdcall*)()>(GetProcAddress(dll,"DllCanUnloadNow"));
    assert(create&&unload&&unload()==S_OK);
    for(int i=0;i<100;++i){
        ComPtr<IClassFactory> factory;assert(SUCCEEDED(create(CLSID_Games,IID_PPV_ARGS(&factory))));
        ComPtr<IShellFolder2> folder;assert(SUCCEEDED(factory->CreateInstance(nullptr,IID_PPV_ARGS(&folder))));
        ComPtr<IPersistFolder2> persist;assert(SUCCEEDED(folder.As(&persist)));
        PIDLIST_ABSOLUTE desktop=nullptr;assert(SUCCEEDED(SHGetKnownFolderIDList(FOLDERID_Desktop,0,nullptr,&desktop)));
        assert(SUCCEEDED(persist->Initialize(desktop)));CoTaskMemFree(desktop);
        ComPtr<IShellView> first,second;assert(SUCCEEDED(folder->CreateViewObject(nullptr,IID_PPV_ARGS(&first))));assert(SUCCEEDED(folder->CreateViewObject(nullptr,IID_PPV_ARGS(&second))));assert(first.Get()!=second.Get());
        HWND window=nullptr;assert(SUCCEEDED(first->GetWindow(&window))&&window==nullptr);
        ComPtr<IEnumIDList> items;assert(SUCCEEDED(folder->EnumObjects(nullptr,SHCONTF_FOLDERS,&items)));PITEMID_CHILD item=nullptr;ULONG fetched=99;assert(items->Next(1,&item,&fetched)==S_FALSE&&fetched==0);
        assert(unload()==S_FALSE);assert(SUCCEEDED(first->DestroyViewWindow()));
    }
    assert(unload()==S_OK);
    HWND parent=CreateWindowExW(0,L"STATIC",L"Games test host",WS_OVERLAPPEDWINDOW,0,0,1000,700,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    assert(parent);ComPtr<IShellBrowser> host;host.Attach(new TestBrowser(parent));
    for(int i=0;i<4;++i){
        ComPtr<IClassFactory> factory;assert(SUCCEEDED(create(CLSID_Games,IID_PPV_ARGS(&factory))));
        ComPtr<IShellFolder> folder;assert(SUCCEEDED(factory->CreateInstance(nullptr,IID_PPV_ARGS(&folder))));
        ComPtr<IShellView> view;assert(SUCCEEDED(folder->CreateViewObject(nullptr,IID_PPV_ARGS(&view))));
        ComPtr<IFolderView> fv;assert(SUCCEEDED(view.As(&fv)));ComPtr<IExplorerPaneVisibility> panes;assert(SUCCEEDED(fv->GetFolder(IID_PPV_ARGS(&panes))));
        EXPLORERPANESTATE pane{};assert(SUCCEEDED(panes->GetPaneState(EP_DetailsPane,&pane))&&(pane&EPS_FORCE));
        RECT rect{0,0,1000,700};FOLDERSETTINGS settings{FVM_ICON,0};HWND child=nullptr;
        assert(SUCCEEDED(view->CreateViewWindow(nullptr,&settings,host.Get(),&rect,&child))&&IsWindow(child));
        if(i==0)PumpFor(4000); // Complete one real WebView startup, then exercise destruction during pending creation.
        assert(SUCCEEDED(view->DestroyViewWindow()));assert(!IsWindow(child));
    }
    host.Reset();DestroyWindow(parent);
    for(int i=0;i<100&&unload()!=S_OK;++i)PumpFor(100);
    assert(unload()==S_OK);WNDCLASSW cls{};assert(!GetClassInfoW(dll,L"GamesCoverflowView",&cls));
    FreeLibrary(dll);CoUninitialize();wprintf(L"PASS: 100 COM lifecycles; real WebView window creation, pending-startup teardown, pane integration and window-class cleanup.\n");return 0;
}
