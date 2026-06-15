After compiling the WebRTC framework, replace all occurences of
#import "sdk/objc/base/RTCMacros.h"
with
#import "RTCMacros.h"
in .h files.
To do so on macOS, from the ./ExternalDependencies/XCFrameworks/WebRTC.xcframework folder:
# find . -type f -name "*.h" -exec sed -i '' 's|sdk/objc/base/RTCMacros.h|RTCMacros.h|g' {} +
