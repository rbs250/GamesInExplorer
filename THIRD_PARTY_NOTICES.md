# Third-party notices

This source uses the Microsoft Edge WebView2 API and links against
`WebView2LoaderStatic.lib` when built. The Microsoft.Web.WebView2 SDK is obtained
separately from the [official NuGet package](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4258.31).
The tested SDK version is **1.0.4258.31**. Its package metadata identifies
Microsoft as author and carries its own `LICENSE.txt` and `NOTICE.txt`.
Review those files in the downloaded package before distributing a binary.
The WebView2 Runtime is supplied separately by Microsoft and is required on
the user's PC.

This repository does not include the SDK, runtime, their libraries, or other
third-party binaries. The MIT license in this repository covers the original
project source only; it does not relicense Microsoft components or any game
art, titles, metadata, or screenshots users may obtain at runtime.
