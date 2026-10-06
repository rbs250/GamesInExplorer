#include "common.h"
#include "steam_target.h"
#include <algorithm>
#include <cwctype>
#include <new>
#include <utility>

static constexpr wchar_t Page[] = L"https://games.local/index.html";
static constexpr UINT PickArtworkMessage=WM_APP+7;
struct ViewState : std::enable_shared_from_this<ViewState> {
    HWND window=nullptr; bool alive=true; HANDLE scan=nullptr; bool artworkScan=false; bool pickerActive=false;
    std::wstring pendingArtworkId;
    ComPtr<ICoreWebView2Controller> controller; ComPtr<ICoreWebView2> web;
    std::wstring error=L"Opening your game library…";
    ViewState(){InterlockedIncrement(&g_objects);}
    ~ViewState(){if(scan)CloseHandle(scan);InterlockedDecrement(&g_objects);}
    void Fail(const std::wstring& message){error=message;if(window)InvalidateRect(window,nullptr,TRUE);}
    void Reply(const wchar_t* message){if(web&&alive)web->PostWebMessageAsString(message);}
    void Resize(){if(controller&&window){RECT rect{};GetClientRect(window,&rect);controller->put_Bounds(rect);}}
};
static bool ValidId(const std::wstring& id) {
    if(id.size()>80)return false;
    if(id.rfind(L"steam-",0)==0)return id.size()>6 && std::all_of(id.begin()+6,id.end(),[](wchar_t c){return c>=L'0'&&c<=L'9';});
    if(id.rfind(L"local-",0)==0)return id.size()==22 && std::all_of(id.begin()+6,id.end(),[](wchar_t c){return (c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f');});
    return false;
}
static bool KnownId(const std::wstring& id) {
    if(!ValidId(id))return false;
    wchar_t target[32768]{};
    auto ini=ModuleFolder()+L"\\web\\launch.ini";
    GetPrivateProfileStringW(id.c_str(),L"target",L"",target,32768,ini.c_str());
    return target[0]!=0;
}
static void OpenSource(ViewState& s,const std::wstring& id) {
    if(!KnownId(id)){s.Reply(L"error:This game is no longer in your library. Refresh and try again.");return;}
    wchar_t website[512]{};
    auto ini=ModuleFolder()+L"\\web\\launch.ini";
    GetPrivateProfileStringW(id.c_str(),L"website",L"",website,512,ini.c_str());
    std::wstring url=website;
    bool allowed=false;
    if(id.rfind(L"steam-",0)==0)allowed=url==L"https://store.steampowered.com/app/"+id.substr(6)+L"/";
    if(!allowed){s.Reply(L"error:No trusted source page is available for this game.");return;}
    SHELLEXECUTEINFOW info{sizeof(info)};info.fMask=SEE_MASK_FLAG_NO_UI;info.hwnd=s.window;info.lpVerb=L"open";info.lpFile=url.c_str();info.nShow=SW_SHOWNORMAL;
    if(!ShellExecuteExW(&info))s.Reply(L"error:Windows could not open the source page.");
}
static void Launch(ViewState& s,const std::wstring& id,bool folder) {
    if(!ValidId(id)){s.Reply(L"error:Invalid game selection. Refresh your library.");return;}
    wchar_t target[32768]{};
    auto ini=ModuleFolder()+L"\\web\\launch.ini";
    GetPrivateProfileStringW(id.c_str(),folder?L"folder":L"target",L"",target,32768,ini.c_str());
    std::wstring destination=target;
    bool valid=false;
    auto steamAction=SteamTargetAction::None;
    if(folder)valid=PathIsDirectoryW(target)!=FALSE;
    else if(id.rfind(L"steam-",0)==0){steamAction=ClassifySteamTarget(id,destination);valid=steamAction!=SteamTargetAction::None;}
    else valid=PathFileExistsW(target)&&_wcsicmp(PathFindExtensionW(target),L".lnk")==0;
    if(!valid){s.Reply(L"error:This game is no longer available. Refresh your library.");return;}
    SHELLEXECUTEINFOW info{sizeof(info)};info.fMask=SEE_MASK_FLAG_NO_UI;info.hwnd=s.window;info.lpVerb=L"open";info.lpFile=target;info.nShow=SW_SHOWNORMAL;
    if(!ShellExecuteExW(&info))s.Reply(L"error:Windows could not open this game. Check its launcher and try again.");
    else if(!folder)s.Reply(steamAction==SteamTargetAction::Install?L"install-requested":L"launched");
}
static std::wstring QuoteArgument(const std::wstring& value) {
    std::wstring quoted=L"\"";
    size_t slashes=0;
    for(wchar_t character:value){
        if(character==L'\\'){++slashes;continue;}
        if(character==L'"'){quoted.append(slashes*2+1,L'\\');quoted.push_back(character);slashes=0;continue;}
        quoted.append(slashes,L'\\');slashes=0;quoted.push_back(character);
    }
    quoted.append(slashes*2,L'\\');quoted.push_back(L'"');
    return quoted;
}
static void Scan(ViewState& s,bool add,const std::wstring& artworkId=L"",const std::wstring& artworkSource=L"") {
    if(s.scan){s.Reply(L"error:A library scan is already running.");return;}
    if(!artworkId.empty()&&!KnownId(artworkId)){s.Reply(L"error:This game is no longer in your library. Refresh and try again.");return;}
    if(!artworkSource.empty()&&(artworkId.empty()||artworkSource.find(L'"')!=std::wstring::npos)){
        s.Reply(L"error:The selected image path is invalid.");return;
    }
    wchar_t system[MAX_PATH]{};GetSystemDirectoryW(system,MAX_PATH);
    std::wstring executable=std::wstring(system)+L"\\WindowsPowerShell\\v1.0\\powershell.exe";
    std::wstring command=QuoteArgument(executable)+L" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "+QuoteArgument(ModuleFolder()+L"\\Scan-Library.ps1")+(add?L" -AddGame":L"");
    if(!artworkId.empty())command+=L" -ArtworkId "+QuoteArgument(artworkId);
    if(!artworkSource.empty())command+=L" -ArtworkSource "+QuoteArgument(artworkSource);
    STARTUPINFOW start{sizeof(start)};start.dwFlags=STARTF_USESHOWWINDOW;start.wShowWindow=SW_HIDE;PROCESS_INFORMATION process{};
    if(CreateProcessW(executable.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&start,&process)){
        CloseHandle(process.hThread);s.scan=process.hProcess;s.artworkScan=!artworkId.empty();SetTimer(s.window,2,200,nullptr);
    }else s.Reply(L"error:Could not scan games. Reopen the Games folder and try again.");
}
static void PickArtwork(ViewState& s,const std::wstring& id) {
    if(!s.alive||!s.window)return;
    if(!KnownId(id)){s.Reply(L"error:This game is no longer in your library. Refresh and try again.");return;}
    if(s.scan){s.Reply(L"error:A library scan is already running.");return;}
    ComPtr<IFileOpenDialog> dialog;
    auto hr=CoCreateInstance(CLSID_FileOpenDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(dialog.GetAddressOf()));
    if(FAILED(hr)){s.Reply(L"error:Windows could not open the image picker.");return;}
    DWORD options=0;
    hr=dialog->GetOptions(&options);
    if(SUCCEEDED(hr))hr=dialog->SetOptions(options|FOS_FORCEFILESYSTEM|FOS_FILEMUSTEXIST|FOS_PATHMUSTEXIST|FOS_NOCHANGEDIR);
    const COMDLG_FILTERSPEC filter[]={{L"Images (*.png; *.jpg; *.jpeg; *.bmp)",L"*.png;*.jpg;*.jpeg;*.bmp"}};
    if(SUCCEEDED(hr))hr=dialog->SetFileTypes(1,filter);
    if(SUCCEEDED(hr))hr=dialog->SetTitle(L"Choose cover art");
    PWSTR pictures=nullptr;
    if(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Pictures,0,nullptr,&pictures))){
        ComPtr<IShellItem> folder;
        if(SUCCEEDED(SHCreateItemFromParsingName(pictures,nullptr,IID_PPV_ARGS(folder.GetAddressOf()))))dialog->SetDefaultFolder(folder.Get());
    }
    CoTaskMemFree(pictures);
    if(FAILED(hr)){s.Reply(L"error:Windows could not prepare the image picker.");return;}
    HWND owner=s.window?GetAncestor(s.window,GA_ROOT):nullptr;
    hr=dialog->Show(owner?owner:s.window);
    if(hr==HRESULT_FROM_WIN32(ERROR_CANCELLED)){s.Reply(L"cancelled");return;}
    if(FAILED(hr)){s.Reply(L"error:Windows could not select that image.");return;}
    ComPtr<IShellItem> selected;
    if(FAILED(dialog->GetResult(selected.GetAddressOf()))){s.Reply(L"error:Windows could not read that image selection.");return;}
    PWSTR filename=nullptr;
    hr=selected->GetDisplayName(SIGDN_FILESYSPATH,&filename);
    std::wstring path=SUCCEEDED(hr)&&filename?filename:L"";
    CoTaskMemFree(filename);
    if(path.empty()||path.find(L'"')!=std::wstring::npos||PathIsRelativeW(path.c_str())){
        s.Reply(L"error:The selected image path is invalid.");return;
    }
    if(!s.alive||!s.window||!IsWindow(s.window))return;
    Scan(s,false,id,path);
}
static void QueueArtwork(ViewState& s,const std::wstring& id) {
    if(!s.alive||!s.window)return;
    if(!KnownId(id)){s.Reply(L"error:This game is no longer in your library. Refresh and try again.");return;}
    if(s.scan||s.pickerActive||!s.pendingArtworkId.empty()){
        s.Reply(L"error:A cover selection or library scan is already running.");return;
    }
    s.pendingArtworkId=id;
    if(!PostMessageW(s.window,PickArtworkMessage,0,0)){
        s.pendingArtworkId.clear();
        s.Reply(L"error:Windows could not open the image picker.");
    }
}
static LRESULT CALLBACK ViewProc(HWND window,UINT msg,WPARAM wp,LPARAM lp) {
    auto state=reinterpret_cast<ViewState*>(GetWindowLongPtrW(window,GWLP_USERDATA));
    if(msg==WM_NCCREATE){state=static_cast<ViewState*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(state));state->window=window;}
    if(!state)return DefWindowProcW(window,msg,wp,lp);
    switch(msg){
    case PickArtworkMessage:{
        if(!state->alive||!state->window||state->pickerActive||state->pendingArtworkId.empty())return 0;
        auto keepAlive=state->shared_from_this();(void)keepAlive;
        std::wstring id=std::move(state->pendingArtworkId);state->pendingArtworkId.clear();
        state->pickerActive=true;
        PickArtwork(*state,id);
        state->pickerActive=false;
        return 0;
    }
    case WM_SIZE:state->Resize();return 0;
    case WM_SETFOCUS:if(state->controller)state->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);return 0;
    case WM_ERASEBKGND:return 1;
    case WM_PAINT:{PAINTSTRUCT ps{};auto dc=BeginPaint(window,&ps);RECT r{};GetClientRect(window,&r);auto brush=CreateSolidBrush(RGB(20,22,24));FillRect(dc,&r,brush);DeleteObject(brush);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(224,230,227));DrawTextW(dc,state->error.c_str(),-1,&r,DT_CENTER|DT_VCENTER|DT_SINGLELINE);EndPaint(window,&ps);return 0;}
    case WM_TIMER:if(wp==2&&state->scan){DWORD code=STILL_ACTIVE;if(GetExitCodeProcess(state->scan,&code)&&code!=STILL_ACTIVE){CloseHandle(state->scan);state->scan=nullptr;KillTimer(window,2);bool artwork=state->artworkScan;state->artworkScan=false;
        if(code==0)state->Reply(artwork?L"artwork-updated":L"refreshed");
        else if(artwork&&code==2)state->Reply(L"cancelled");
        else if(artwork&&code==4)state->Reply(L"error:Could not import this cover. Use a valid PNG, JPEG or BMP up to 25 MB, and check that the Games folder is writable.");
        else if(code==5)state->Reply(L"error:A library scan is already running. Try again shortly.");
        else state->Reply(artwork?L"error:The cover refresh did not finish. Use Refresh to try again.":L"error:Library scan failed. Try Refresh again.");}}return 0;
    case WM_NCDESTROY:KillTimer(window,2);state->alive=false;state->pendingArtworkId.clear();state->window=nullptr;SetWindowLongPtrW(window,GWLP_USERDATA,0);return DefWindowProcW(window,msg,wp,lp);
    }
    return DefWindowProcW(window,msg,wp,lp);
}
static void StartWebView(const std::shared_ptr<ViewState>& s) {
    wchar_t local[MAX_PATH]{};SHGetFolderPathW(nullptr,CSIDL_LOCAL_APPDATA,nullptr,SHGFP_TYPE_CURRENT,local);
    std::wstring userData=std::wstring(local)+L"\\GamesCoverflow\\WebViewData";
    auto hr=CreateCoreWebView2EnvironmentWithOptions(nullptr,userData.c_str(),nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([s](HRESULT error,ICoreWebView2Environment* environment)->HRESULT{
            if(!s->alive)return S_OK;
            if(FAILED(error)||!environment){s->Fail(L"Microsoft Edge WebView2 Runtime is required. Install it, then reopen Games.");return S_OK;}
            auto result=environment->CreateCoreWebView2Controller(s->window,Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([s](HRESULT error,ICoreWebView2Controller* controller)->HRESULT{
                if(!s->alive){if(controller)controller->Close();return S_OK;}
                if(FAILED(error)||!controller){s->Fail(L"Could not open the game view. Close this tab and try again.");return S_OK;}
                s->controller=controller;controller->get_CoreWebView2(&s->web);s->Resize();
                ComPtr<ICoreWebView2Settings> settings;s->web->get_Settings(&settings);
                settings->put_AreDevToolsEnabled(FALSE);settings->put_AreDefaultContextMenusEnabled(FALSE);settings->put_IsStatusBarEnabled(FALSE);
                ComPtr<ICoreWebView2_3> modern;
                if(FAILED(s->web.As(&modern))){s->Fail(L"Update Microsoft Edge WebView2 Runtime, then reopen Games.");return S_OK;}
                auto mapping=modern->SetVirtualHostNameToFolderMapping(L"games.local",(ModuleFolder()+L"\\web").c_str(),COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);
                if(FAILED(mapping)){s->Fail(L"The Games library files could not be loaded. Reinstall Games Coverflow.");return S_OK;}
                // Weak callbacks avoid a COM event/source ownership cycle.
                std::weak_ptr<ViewState> weak=s;EventRegistrationToken token{};
                s->web->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>([](ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs* args)->HRESULT{
                    LPWSTR uri=nullptr;args->get_Uri(&uri);if(!uri||wcscmp(uri,Page)!=0)args->put_Cancel(TRUE);CoTaskMemFree(uri);return S_OK;
                }).Get(),&token);
                s->web->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>([](ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs* args)->HRESULT{args->put_Handled(TRUE);return S_OK;}).Get(),&token);
                s->web->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>([weak](ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs* args)->HRESULT{
                    auto state=weak.lock();if(!state||!state->alive)return S_OK;
                    LPWSTR source=nullptr;args->get_Source(&source);bool trusted=source&&wcscmp(source,Page)==0;CoTaskMemFree(source);if(!trusted)return S_OK;
                    LPWSTR raw=nullptr;if(FAILED(args->TryGetWebMessageAsString(&raw)))return S_OK;std::wstring message=raw?raw:L"";CoTaskMemFree(raw);
                    if(message.rfind(L"launch:",0)==0)Launch(*state,message.substr(7),false);
                    else if(message.rfind(L"folder:",0)==0)Launch(*state,message.substr(7),true);
                    else if(message==L"refresh")Scan(*state,false);
                    else if(message==L"add")Scan(*state,true);
                    else if(message.rfind(L"artwork:",0)==0)QueueArtwork(*state,message.substr(8));
                    else if(message.rfind(L"source:",0)==0)OpenSource(*state,message.substr(7));
                    return S_OK;
                }).Get(),&token);
                s->web->Navigate(Page);controller->put_IsVisible(TRUE);return S_OK;
            }).Get());
            if(FAILED(result))s->Fail(L"The game view could not start. Reopen the Games folder.");return S_OK;
        }).Get());
    if(FAILED(hr))s->Fail(L"WebView2 could not start. Install Microsoft Edge WebView2 Runtime and reopen Games.");
}
class GamesView final : public IShellView,public IFolderView {
    long refs=1; std::shared_ptr<ViewState> state=std::make_shared<ViewState>();ComPtr<IShellBrowser> browser;ComPtr<IShellFolder> folder;FOLDERSETTINGS settings{FVM_ICON,0};
public:
    explicit GamesView(IShellFolder* owner):folder(owner){InterlockedIncrement(&g_objects);}~GamesView(){DestroyViewWindow();InterlockedDecrement(&g_objects);}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override{if(!out)return E_POINTER;*out=nullptr;if(id==IID_IUnknown||id==IID_IOleWindow||id==IID_IShellView)*out=static_cast<IShellView*>(this);else if(id==IID_IFolderView)*out=static_cast<IFolderView*>(this);if(!*out)return E_NOINTERFACE;AddRef();return S_OK;}
    ULONG STDMETHODCALLTYPE AddRef() override{return InterlockedIncrement(&refs);}ULONG STDMETHODCALLTYPE Release() override{auto n=InterlockedDecrement(&refs);if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE GetWindow(HWND* out) override{if(!out)return E_POINTER;*out=state->window;return S_OK;}
    HRESULT STDMETHODCALLTYPE ContextSensitiveHelp(BOOL) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE TranslateAccelerator(MSG*) override{return S_FALSE;}
    HRESULT STDMETHODCALLTYPE EnableModeless(BOOL) override{return S_OK;}
    HRESULT STDMETHODCALLTYPE UIActivate(UINT activation) override{if(activation!=SVUIA_DEACTIVATE&&browser)browser->OnViewWindowActive(this);if(activation==SVUIA_ACTIVATE_FOCUS&&state->controller)state->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);return S_OK;}
    HRESULT STDMETHODCALLTYPE Refresh() override{if(state->web)Scan(*state,false);return S_OK;}
    HRESULT STDMETHODCALLTYPE CreateViewWindow(IShellView*,LPCFOLDERSETTINGS value,IShellBrowser* host,RECT* rect,HWND* out) override{
        if(!host||!rect||!out)return E_POINTER;*out=nullptr;browser=host;if(value)settings=*value;
        HWND parent=nullptr;auto hr=host->GetWindow(&parent);if(FAILED(hr))return hr;
        WNDCLASSW wc{};wc.lpfnWndProc=ViewProc;wc.hInstance=g_instance;wc.hCursor=LoadCursor(nullptr,IDC_ARROW);wc.lpszClassName=L"GamesCoverflowView";RegisterClassW(&wc);
        state->alive=true;
        auto window=CreateWindowExW(0,wc.lpszClassName,L"Games",WS_CHILD|WS_VISIBLE|WS_CLIPCHILDREN|WS_CLIPSIBLINGS,rect->left,rect->top,rect->right-rect->left,rect->bottom-rect->top,parent,nullptr,g_instance,state.get());
        if(!window){browser.Reset();return HRESULT_FROM_WIN32(GetLastError());}
        *out=window;StartWebView(state);return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DestroyViewWindow() override{state->alive=false;if(state->controller){state->controller->Close();state->controller.Reset();state->web.Reset();}if(state->window)DestroyWindow(state->window);browser.Reset();return S_OK;}
    HRESULT STDMETHODCALLTYPE GetCurrentInfo(LPFOLDERSETTINGS out) override{if(!out)return E_POINTER;*out=settings;return S_OK;}
    HRESULT STDMETHODCALLTYPE AddPropertySheetPages(DWORD,LPFNSVADDPROPSHEETPAGE,LPARAM) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE SaveViewState() override{return S_OK;}
    HRESULT STDMETHODCALLTYPE SelectItem(PCUITEMID_CHILD,SVSIF) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetItemObject(UINT,REFIID,void** out) override{if(out)*out=nullptr;return E_NOINTERFACE;}
    HRESULT STDMETHODCALLTYPE GetCurrentViewMode(UINT* out) override{if(!out)return E_POINTER;*out=FVM_ICON;return S_OK;}
    HRESULT STDMETHODCALLTYPE SetCurrentViewMode(UINT) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetFolder(REFIID id,void** out) override{return folder->QueryInterface(id,out);}
    HRESULT STDMETHODCALLTYPE Item(int,PITEMID_CHILD* out) override{if(out)*out=nullptr;return E_INVALIDARG;}
    HRESULT STDMETHODCALLTYPE ItemCount(UINT,int* out) override{if(!out)return E_POINTER;*out=0;return S_OK;}
    HRESULT STDMETHODCALLTYPE Items(UINT,REFIID,void** out) override{if(out)*out=nullptr;return E_NOINTERFACE;}
    HRESULT STDMETHODCALLTYPE GetSelectionMarkedItem(int* out) override{if(out)*out=-1;return S_FALSE;}
    HRESULT STDMETHODCALLTYPE GetFocusedItem(int* out) override{if(out)*out=-1;return S_FALSE;}
    HRESULT STDMETHODCALLTYPE GetItemPosition(PCUITEMID_CHILD,POINT* out) override{if(out)*out={0,0};return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetSpacing(POINT* out) override{if(out)*out={0,0};return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetDefaultSpacing(POINT* out) override{if(out)*out={0,0};return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE GetAutoArrange() override{return S_OK;}
    HRESULT STDMETHODCALLTYPE SelectItem(int,DWORD) override{return E_NOTIMPL;}
    HRESULT STDMETHODCALLTYPE SelectAndPositionItems(UINT,PCUITEMID_CHILD_ARRAY,POINT*,DWORD) override{return E_NOTIMPL;}
};
HRESULT CreateGamesView(IShellFolder* folder,REFIID id,void** out){if(!out)return E_POINTER;*out=nullptr;auto view=new(std::nothrow)GamesView(folder);if(!view)return E_OUTOFMEMORY;auto hr=view->QueryInterface(id,out);view->Release();return hr;}
