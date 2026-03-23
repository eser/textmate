// TextFellowConfigBridge.mm — Bridges SW3TConfig (Swift) to TextMate settings (C++)
//
// Reads values from LayeredConfig and injects them into the existing
// settings_t system so TOML config values affect the editor.

#if __has_include("TextFellow-Swift.h")

#import <MetalKit/MetalKit.h>
#import "TextFellow-Swift.h"
#import <settings/settings.h>

@interface TextFellowConfigBridge : NSObject
+ (void)applyConfigToSettings;
@end

@implementation TextFellowConfigBridge

+ (void)applyConfigToSettings
{
	LayeredConfig* config = LayeredConfig.shared;

	// Map TOML keys → TextMate settings keys
	struct { NSString* tomlKey; std::string tmKey; } const mappings[] = {
		{ @"editor.tab_size",   kSettingsTabSizeKey   },
		{ @"editor.soft_tabs",  kSettingsSoftTabsKey  },
		{ @"editor.font_name",  kSettingsFontNameKey  },
		{ @"editor.font_size",  kSettingsFontSizeKey  },
		{ @"editor.word_wrap",  kSettingsSoftWrapKey  },
		{ @"theme.editor",      kSettingsThemeKey     },
	};

	for(auto const& m : mappings)
	{
		NSString* value = [config stringValueForKey:m.tomlKey];
		if(value)
		{
			settings_t::set(m.tmKey, std::string(value.UTF8String));
		}
	}

	os_log_info(OS_LOG_DEFAULT, "TextFellowConfigBridge: applied TOML settings to TextMate");
}

@end

#endif
