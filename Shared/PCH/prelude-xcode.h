// prelude-xcode.h — Unified prefix header for Xcode builds
//
// Rave uses per-filetype preludes (prelude.c, prelude.cc, prelude.m).
// Xcode needs a single GCC_PREFIX_HEADER. This file conditionally
// includes the right combination based on __cplusplus and __OBJC__.
//
// NOTE: WebKit's WKWebsiteDataStore.h includes <Network/Network.h> which
// collides with our network/ headers on case-insensitive macOS filesystems.
// This is resolved by a wrapper in Xcode/include/network/network.h that
// provides a stub nw_proxy_config_t type (see gen-header-symlinks.sh).

#ifndef PRELUDE_XCODE_H
#define PRELUDE_XCODE_H

// Macros that Rave passes via -D flags. Defined here because xcconfig
// quoting makes string-literal -D values unreliable. #ifndef guards
// ensure no conflict if both Rave and Xcode builds are used.
#ifndef NULL_STR
#define NULL_STR "\uFFFF"
#endif
#ifndef REST_API
#define REST_API "https://api.textmate.org"
#endif

// Always: C system headers + macOS C frameworks
#include "prelude.c"
#include "prelude-mac.h"

#ifdef __cplusplus
// C++ and ObjC++ files: standard library (BEFORE ObjC frameworks!)
#define __STDC_LIMIT_MACROS
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <deque>
#include <functional>
#include <iterator>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>
#include <memory>
#include <numeric>
#include <random>
#include <thread>
#include <variant>
#endif

#ifdef __OBJC__
// ObjC and ObjC++ files: Cocoa, WebKit, Quartz, etc.
#import <objc/objc-runtime.h>
#import <AddressBook/AddressBook.h>
#import <Cocoa/Cocoa.h>
#import <ExceptionHandling/NSExceptionHandler.h>
#import <CoreFoundation/CFPlugInCOM.h>
#import <Quartz/Quartz.h>
#import <WebKit/WebKit.h>
#endif

#endif /* PRELUDE_XCODE_H */
