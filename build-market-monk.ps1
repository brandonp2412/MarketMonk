Remove-Item -Path market_monk/* -Recurse -Force
cp -r -Force //host.lan/Data/market_monk-source/* market_monk
cd market_monk
dart run msix:create
cp -r -Force build/windows/x64/runner/Release/* //host.lan/Data/market_monk
