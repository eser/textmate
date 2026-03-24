// TextFellowConfigBridge.mm — Bridges SW3TConfig (Swift) to TextMate settings (C++)
//
// Reads values from LayeredConfig and injects them into the existing
// settings_t system so TOML config values affect the editor.

#if __has_include("TextFellow-Swift.h")

#import <MetalKit/MetalKit.h>
#import "TextFellow-Swift.h"
#import <settings/settings.h>
#import <bundles/bundles.h>
#import <oak/misc.h>

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
			std::string strValue(value.UTF8String);

			// Theme key needs UUID, not name — resolve via bundle lookup
			if(m.tmKey == kSettingsThemeKey && strValue.find('-') == std::string::npos)
			{
				// It's a name, not a UUID — look up the theme by name
				for(auto const& item : bundles::query(bundles::kFieldName, strValue, scope::wildcard, bundles::kItemTypeTheme))
				{
					strValue = to_s(item->uuid());
					[NSUserDefaults.standardUserDefaults setObject:@(strValue.c_str()) forKey:@"themeUUID"];
					break;
				}
			}

			settings_t::set(m.tmKey, strValue);
		}
	}

	os_log_info(OS_LOG_DEFAULT, "TextFellowConfigBridge: applied TOML settings to TextMate");
}

@end

#endif
