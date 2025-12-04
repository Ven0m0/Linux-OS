# webview-flags

```sh
adb shell am start -a "com.android.webview.SHOW_DEV_UI"
```

`webview-enable-modern-cookie-same-site` -> `Enabled`

`site-per-process` -> `Enabled`

`WebViewAccelerateSmallCanvases` -> `Enabled`

`WebViewMixedContentAutoupgrades` -> `Enabled`

`GMSCoreEmoji` -> `Disabled`

`AutofillEnableLoyaltyCardsFilling` -> `Disabled` *(This uses Google Wallet)*

`AutofillUKMExperimentalFields` -> `Disabled`

`IPH_AutofillVirtualCardSuggestion` -> `Disabled`

`WebViewXRequestedWithHeaderControl` -> `Enabled`

`WebViewReduceUAAndroidVersionDeviceModel` -> `Enabled`

`ReduceUserAgentMinorVersion` -> `Enabled`

`ViewportHeightClientHintHeader` -> `Disabled`

`UACHOverrideBlank` -> `Enabled`

`DeprecateUnload` -> `Enabled`

`DeprecateUnloadByAllowList` -> `Disabled`

`ReportEventTimingAtVisibilityChange` -> `Disabled`

`WebViewFileSystemAccess` -> `Disabled`

`ReportingServiceAlwaysFlush` -> `Enabled`

`MetricsLogTrimming` -> `Enabled`

`ReduceSubresourceResponseStartedIPC` -> `Enabled`

`PrivacySandboxAdsAPIsOverride` -> `Disabled`

`AddWarningShownTSToClientSafeBrowsingReport` -> `Disabled`

`CreateWarningShownClientSafeBrowsingReports` -> `Disabled`

`ThirdPartyStoragePartitioning` -> `Enabled`

`EnableTLS13EarlyData` -> `Disabled`

`EnablePerfettoSystemTracing` -> `Disabled`

`CollectAndroidFrameTimelineMetrics` -> `Disabled`

`PartitionAllocMemoryReclaimer` -> `Enabled`

`WebViewAutoSAA` -> `Disabled`

`UseRustJsonParser` -> `Enabled`

`WebViewMediaIntegrityApiBlinkExtension` -> `Disabled`

`ThrottleUnimportantFrameTimers` -> `Enabled`

`ReduceTransferSizeUpdatedIPC` -> `Enabled`

`WebViewBackForwardCache` -> `Disabled`

`AccessibilityManageBroadcastReceiverOnBackground` -> `Disabled`

`BackForwardCacheSendNotRestoredReasons` -> `Disabled`

`webview-force-disable-3pcs` -> `Enabled`

`NoThrottlingVisibleAgent` -> `Disabled`

`AllowDatapipeDrainedAsBytesConsumerInBFCache` -> `Disabled`

`LowerHighResolutionTimerThreshold` -> `Enabled`

`InputStreamOptimizations` -> `Enabled`

`EnableHangWatcher` -> `Disabled`

`WebViewDisableCHIPS` -> `Disabled`

`DIPS` -> `Enabled`

`CCSlimming` -> `Enabled`

`AllowSensorsToEnterBfcache` -> `Disabled`

`FetchLaterAPI` -> `Disabled`

`Prerender2FallbackPrefetchSpecRules` -> `Disabled`

`PreloadLinkRelDataUrls` -> `Disabled`

`PrefetchServiceWorker` -> `Disabled`

`OptimizeHTMLElementUrls` -> `Enabled`

`SharedStorageAPI` -> `Disabled`

`HttpCacheNoVarySearch` -> `Disabled`

`PartitionAllocWithAdvancedChecks` -> `Enabled` *([some info](https://groups.google.com/a/chromium.org/g/ios-reviews/c/BY-Xq_Zeds8)*

`SensitiveContent` -> `Enabled` *([info](https://source.chromium.org/chromium/chromium/src/+/main:components/sensitive_content/))*

`RestrictAbusePortsOnLocalhost` -> `Enabled`

`SharedDictionaryCache` -> `Disabled`

`CacheSharingForPervasiveScripts` -> `Disabled`

## for devices without google play services:

`WebViewUseMetricsUploadService` -> `Disabled`

`WebViewUseMetricsUploadServiceOnlySdkRuntime` -> `Disabled`

## for devices with hdr support:

`AndroidHDR` -> `Enabled`
