// Enable loading userChrome.css and userContent.css
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

/** GENERAL ***/
////////////////////////////////////////////////////////////////////////////////////
user_pref("media.videocontrols.picture-in-picture.enabled", false);
user_pref("dom.ipc.processPriorityManager.backgroundUsesEcoQoS", true);
user_pref("dom.iframe_lazy_loading.enabled", true);
user_pref("gfx.webrender.all", true); // enables WR + additional features
user_pref("content.notify.interval", 100000);
user_pref("layers.gpu-process.force-enabled", true); // enforce
user_pref("media.hardware-video-decoding.force-enabled", true); // enforce
user_pref("browser.sessionhistory.max_total_viewers", 2); //limits the maximum number of pages stored in memory
/** GFX ***/
user_pref("gfx.canvas.accelerated", true); // PREF: enable GPU-accelerated Canvas2D [WINDOWS]
user_pref("gfx.canvas.accelerated.cache-items", 8192); // default=2048; Chrome=4096
user_pref("gfx.canvas.accelerated.cache-size", 512); // default=256; Chrome=512
user_pref("gfx.content.skia-font-cache-size", 20); // default=5; Chrome=20
user_pref("gfx.webrender.precache-shaders", true); // longer initial startup time
/** DISK CACHE ***/
user_pref("browser.cache.disk.enable", true); //More efficient to keep the browser cache instead of having to re-download objects for the websites you visit frequently
user_pref("browser.cache.jsbc_compression_level", 9); // PREF: compression level for cached JavaScript bytecode
user_pref("browser.cache.disk.smart_size.enabled", true); // force a fixed max cache size on disk

user_pref("browser.cache.disk.capacity", 256000); // default=256000; size of disk cache; 1024000=1GB
// Higher cache disabled incase of Profile-sync-daemon
//user_pref("browser.cache.disk.capacity", 2097152); // default=256000; size of disk cache; 1024000=1GB
user_pref("browser.cache.disk.max_entry_size", 51200); // DEFAULT (50 MB); maximum size of an object in disk cache
user_pref("browser.cache.disk.metadata_memory_limit", 500); // limit of recent metadata we keep in memory for faster access
user_pref("browser.cache.disk.max_chunks_memory_usage", 40960); // memory limit (in kB) for new cache data not yet written to disk
user_pref("browser.cache.disk.max_priority_chunks_memory_usage", 40960);
user_pref("browser.cache.disk.free_space_soft_limit", 10240); // enforce free space checks
user_pref("browser.cache.disk.free_space_hard_limit", 2048);
/** MEDIA CACHE ***/
user_pref("browser.cache.memory.capacity", -1); // -1=Automatically decide the maximum memory to use to cache decoded images
user_pref("browser.cache.memory.max_entry_size", 10240); // (10 MB); default=5120 (5 MB)
user_pref("media.memory_cache_max_size", 65536); // media memory cache
user_pref("media.memory_caches_combined_limit_kb", 524288); // media cache combine sizes
user_pref("media.memory_caches_combined_limit_pc_sysmem", 5); // percentage of system memory that Firefox can use for media caches
/** IMAGE CACHE ***/
user_pref("image.mem.decode_bytes_at_a_time", 32768); // image cache
/** NETWORK ***/
user_pref("network.http.rcwn.enabled", false); // PREF: Race Cache With Network. Set to false if your intention is to increase cache usage and reduce network usage.
user_pref("network.http.rcwn.small_resource_size_kb", 256); // PREF: attempt to RCWN only if a resource is smaller than this size
user_pref("network.http.max-connections", 1800);
user_pref("network.http.max-persistent-connections-per-server", 20); //increase the absolute number of HTTP connections
user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);
user_pref("network.http.pacing.requests.enabled", true); // reducing network congestion, improving web page loading speed, and avoiding server overload
user_pref("network.ssl_tokens_cache_capacity", 10240); // more TLS token caching (fast reconnects)
user_pref("network.buffer.cache.size", 65535); //Reduce Firefox's CPU usage by requiring fewer application-to-driver data transfers
user_pref("network.buffer.cache.count", 48); //
user_pref("network.dnsCacheEntries", 1000); //increase DNS cache
user_pref("network.dnsCacheExpiration", 3600); //
user_pref("network.dnsCacheExpirationGracePeriod", 240); //adjust DNS expiration time

// Experimental
//user_pref("network.dns.disablePrefetch", true);
//user_pref("network.dns.disablePrefetchFromHTTPS", true);
//user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", false);
user_pref("network.dns.disablePrefetchFromHTTPS", false);
user_pref("network.prefetch-next", true);

user_pref("network.modulepreload", true);
user_pref("network.early-hints.enabled", true);
user_pref("network.early-hints.preconnect.enabled", true);
user_pref("network.early-hints.preconnect.max_connections", 10); 
user_pref("network.preconnect", true); // DEFAULT
user_pref("browser.urlbar.speculativeConnect.enabled", true); // preconnect to the autocomplete URL in the address bar
user_pref("browser.places.speculativeConnect.enabled", true); // Whether to warm up network connections for places:menus and places:toolbar
user_pref("network.fetchpriority.enabled", true);
//user_pref("network.predictor.enabled", false);
//user_pref("network.predictor.enable-prefetch", false);
user_pref("network.predictor.enabled", true);
user_pref("network.predictor.enable-prefetch", true);
user_pref("network.dns.max_high_priority_threads", 40); // DEFAULT [FF 123?]
user_pref("network.dns.max_any_priority_threads", 24); // DEFAULT [FF 123?]

/** EXPERIMENTAL ***/
user_pref("layout.css.grid-template-masonry-value.enabled", true);
user_pref("dom.enable_web_task_scheduling", true);
user_pref("network.http.speculative-parallel-limit", 20); // Speculative loading
// PREF: prevent accessibility services from accessing your browser. Accessibility Service may negatively impact Firefox browsing performance.
user_pref("accessibility.force_disabled", 1);
user_pref("devtools.accessibility.enabled", false);
// Reader supposedly costs extra CPU after page load.
user_pref("reader.parse-on-load.enabled", false); // PREF: disable Reader mode parse on load
// PREF: CRLite is faster and more private than OCSP
user_pref("security.remote_settings.crlite_filters.enabled", true);
user_pref("security.OCSP.enabled", 0);
user_pref("security.pki.crlite_mode", 2);
// DISK AVOIDANCE
user_pref("browser.sessionstore.interval", 60000);
// PREF: unload tabs on low memory
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.low_commit_space_threshold_mb", 25698);
user_pref("browser.tabs.min_inactive_duration_before_unload", 300000); // 5min
// PREF: Process count
user_pref("dom.ipc.processCount", 8);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("dom.ipc.processPrelaunch.fission.number", 1);

/** SECURITY ***/
// PREF: Global Privacy Control (GPC)
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("privacy.globalprivacycontrol.functionality.enabled", true);
user_pref("privacy.globalprivacycontrol.pbmode.enabled", true);
user_pref("extensions.webcompat.enable_shims", true); // PREF: Smartblock, enabled with "Strict"
user_pref("privacy.trackingprotection.lower_network_priority", true); // PREF: lower the priority of network loads for resources on the tracking protection list
// Location
user_pref("permissions.default.geo", 0); // PREF: allow websites to ask you for your location
user_pref("geo.enabled", false);
user_pref("geo.provider.ms-windows-location", false); // [WINDOWS]
user_pref("geo.provider.network.url", "");
user_pref("geo.provider.network.logging.enabled", false); // [HIDDEN PREF]
user_pref("permissions.default.desktop-notification", 0); // PREF: allow websites to ask you to receive site notifications
user_pref("privacy.donottrackheader.enabled", true); // Enable the DNT (Do Not Track) HTTP header
user_pref("urlclassifier.trackingSkipURLs", "*.reddit.com, *.twitter.com, *.twimg.com, *.tiktok.com");
user_pref("urlclassifier.features.socialtracking.skipURLs", "*.instagram.com, *.twitter.com, *.twimg.com");
/** USABILITY ***/
user_pref("image.jxl.enabled", true); // PREF: JPEG XL image format
user_pref("browser.urlbar.trimHttps", true);
/** COOKIE BANNER HANDLING ***/
user_pref("cookiebanners.service.mode", 2);
user_pref("cookiebanners.service.mode.privateBrowsing", 2);
/** FULLSCREEN NOTICE + Delays ***/
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");
// PREF: disable fullscreen notice
user_pref("full-screen-api.warning.timeout", 0);
user_pref("full-screen-api.warning.delay", -1);
user_pref("toolkit.cosmeticAnimations.enabled", false); // Animations
user_pref("security.dialog_enable_delay", 0);
user_pref("browser.fullscreen.animateUp", false);
// PREF: use DirectWrite everywhere like Chrome
user_pref("gfx.font_rendering.cleartype_params.rendering_mode", 5);
user_pref("gfx.font_rendering.cleartype_params.cleartype_level", 100);
user_pref("gfx.font_rendering.cleartype_params.force_gdi_classic_for_families", "");
user_pref("gfx.font_rendering.directwrite.use_gdi_table_loading", false);
user_pref("gfx.font_rendering.cleartype_params.pixel_structure", 1);
/** NEW TAB PAGE ***/
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.showWeather", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false); // Disable "Recommend extensions as you browse"
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false); // Disable "Recommend features as you browse"
user_pref("browser.preferences.moreFromMozilla", false);
user_pref("browser.aboutwelcome.enabled", false);
// PREF: minimize URL bar suggestions
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.clipboard", false);
user_pref("browser.urlbar.trending.featureGate", false); // PREF: disable urlbar trending search suggestions
user_pref("browser.download.open_pdf_attachments_inline", true); // PREF: open PDFs inline
user_pref("browser.urlbar.suggest.weather", false);
user_pref("browser.urlbar.suggest.calculator", false);
user_pref("browser.download.start_downloads_in_tmp_dir", true);
/** HEADERS / REFERERS ***/
user_pref("network.http.referer.XOriginTrimmingPolicy", 2);
// Enable WebM
user_pref("media.mediasource.webm.enabled", true);
// Disable notifications
user_pref("dom.webnotifications.enabled", false);
user_pref("dom.webnotifications.serviceworker.enabled", false);
user_pref("extensions.screenshots.upload-disabled", true); // Disable "Upload" feature on Screenshots
user_pref("browser.aboutConfig.showWarning", false); // Don't warn when opening about:config 
user_pref("layout.word_select.eat_space_to_next_word", true); // When double-clicking a word on a page, only copy the word itself, not the space character next to it 
// Autoplay
user_pref("media.block-autoplay-until-in-foreground", true);
// PREF: restore "View image info" on right-click
user_pref("browser.menu.showViewImageInfo", true);
// PREF: insert new tabs after groups like it
user_pref("browser.tabs.insertRelatedAfterCurrent", true); // DEFAULT
/** TELEMETRY ***/
user_pref("dom.event.clipboardevents.enabled", false);
user_pref("media.navigator.enabled", false);
user_pref("network.cookie.cookieBehavior", 1;
user_pref("dom.private-attribution.submission.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false); // Disable check for default browser
user_pref("browser.newtabpage.activity-stream.default.sites", ""); // new tab page
user_pref("browser.newtab.preload", false);
user_pref("browser.onboarding.enabled", false);        // Hide onboarding tour (uses Google Analytics)
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.server", "");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);
user_pref("toolkit.coverage.opt-out", true);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.discovery.enabled", false);  // Disable "Allow Firefox to make personalized extension recommendations"
user_pref("browser.send_pings", false);
user_pref("dom.battery.enabled", false);
user_pref("beacon.enabled", false); // Disable sending additional analytics to web servers
user_pref("corroborator.enabled", false); // Skip checking omni.ja and other files
user_pref("signon.firefoxRelay.feature", ""); // PREF: disable Firefox Relay
user_pref("extensions.pocket.enabled", false); // Disable Pocket
user_pref("extensions.pocket.api"," "); //
user_pref("extensions.pocket.oAuthConsumerKey", " "); //
user_pref("extensions.pocket.site", " "); //
user_pref("extensions.pocket.showHome", false); //
user_pref("browser.download.manager.addToRecentDocs", false);
// Disable Activity Stream recent Highlights in the Library
user_pref("browser.library.activity-stream.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includeBookmarks", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includeDownloads", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includeVisited", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includePocket", false);
user_pref("browser.newtabpage.activity-stream.telemetry.ping.endpoint", ""); // Disable Activity Stream telemetry
// Disable Activity Stream Snippets (runs code from a remote server)
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
user_pref("browser.newtabpage.activity-stream.asrouter.providers.snippets", "");
// Disable other stuff
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
// Disable add-on recommendations
user_pref("extensions.getAddons.showPane", false);  // Disable about:addons "Recommendations" (uses Google Analytics) [HIDDEN PREF]
user_pref("extensions.htmlaboutaddons.discover.enabled", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
// Opt-out of Shield studies and Normandy
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
/** CRASH REPORTS ***/
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
user_pref("network.connectivity-service.enabled", false); //  Do NOT use for mobile devices. May NOT be able to use Firefox on public wifi (hotels, coffee shops, etc).
user_pref("default-browser-agent.enabled", false); // PREF: software that continually reports what default browser you are using
user_pref("extensions.abuseReport.enabled", false); // PREF: "report extensions for abuse"
user_pref("browser.search.serpEventTelemetryCategorization.enabled", false); // PREF: SERP Telemetry
// PREF: assorted telemetry, shouldn't be needed for user.js, but browser forks may want to disable these prefs.
user_pref("dom.security.unexpected_system_load_telemetry_enabled", false);
user_pref("network.trr.confirmation_telemetry_enabled", false);
user_pref("security.app_menu.recordEventTelemetry", false);
user_pref("security.certerrors.recordEventTelemetry", false);
user_pref("security.protectionspopup.recordEventTelemetry", false);
user_pref("privacy.trackingprotection.emailtracking.data_collection.enabled", false);
user_pref("messaging-system.askForFeedback", false);
// Logging
user_pref("extensions.logging.enabled ", false);
user_pref("browser.search.log", false);
user_pref("devtools.webconsole.filter.log", false);
// Other
user_pref("browser.shopping.experience2023.ads.enabled", false);
user_pref("browser.shopping.experience2023.ads.userEnabled", false);
user_pref("network.trr.disable-ECS", false);
user_pref("browser.tabs.hoverPreview.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.urlbar.suggest.pocket", false);
user_pref("dom.element.blocking.enabled", true);
user_pref("dom.gamepad.enabled", false);
user_pref("media.gmp.decoder.multithreaded", true);
user_pref("media.gmp.encoder.multithreaded", true);
user_pref("narrate.enabled", false);
user_pref("permissions.default.camera", 0);
user_pref("print.enabled", false);
user_pref("privacy.query_stripping.enabled", true);
user_pref("privacy.fingerprintingProtection", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.spoof_english", 0);
user_pref("sidebar.animation.enabled", false);
user_pref("extensions.webextensions.restrictedDomains", ""); // remove Mozilla domains so adblocker works on pages
// PREF: Mozilla VPN
user_pref("browser.privatebrowsing.vpnpromourl", "");
user_pref("browser.vpn_promo.enabled", false);
// PREF: disable about:addons' Recommendations pane (uses Google Analytics)
user_pref("extensions.getAddons.showPane", false); // HIDDEN
// PREF: disable recommendations in about:addons' Extensions and Themes panes
user_pref("browser.discovery.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.aboutwelcome.enabled", false); // disable Intro screens
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
// PREF: add compact mode back to options
user_pref("browser.compactmode.show", true);
user_pref("layout.css.prefers-color-scheme.content-override", 0); // Dark color scheme for websites
// Cookie banner
user_pref("cookiebanners.service.mode", 1);
user_pref("cookiebanners.service.mode.privateBrowsing", 1);
user_pref("cookiebanners.service.enableGlobalRules", true);
user_pref("cookiebanners.service.enableGlobalRules.subFrames", true);
user_pref("toolkit.telemetry.pioneer-new-studies-available", false);
user_pref("toolkit.telemetry.pioneerId", "");
user_pref("toolkit.telemetry.log.level", "Fatal");
user_pref("toolkit.telemetry.log.dump", "Fatal");
user_pref("toolkit.telemetry.shutdownPingSender.enabledFirstSession", false);
user_pref("toolkit.telemetry.prioping.enabled", false);
user_pref("toolkit.telemetry.cachedClientID", "");
// HTTP/3 fix
user_pref("network.dns.httpssvc.http3_fast_fallback_timeout", 0);
// Media tweaks
user_pref("media.gmp.decoder.multithreaded", true);
user_pref("media.gmp.encoder.multithreaded", true);
user_pref("media.av1.new-thread-count-strategy", true);
user_pref("media.webrtc.simulcast.av1.enabled", false);
user_pref("image.decode-immediately.enabled", true);
user_pref("media.gmp.decoder.decode_batch", true);
user_pref("media.decoder.recycle.enabled", true);
user_pref("media.peerconnection.video.vp9_preferred", true);
