## 0.0.5

* Redesigned inspector UI with a modern look: card-based request list, segmented pill tabs, color-coded HTTP method and status chips, refreshed search, filters, empty states, and toasts.
* New collapsible JSON tree view for request/response bodies — expand/collapse any object or array, with expand-all / collapse-all controls and syntax coloring (light & dark).
* New body view modes: Tree / Pretty / Raw for JSON, Pretty / Raw for XML/HTML.
* Request detail page now shows a summary card with the full URL (tap the link icon to copy) and status, duration, response size, and time chips; opens on the Response tab by default.
* Long-press any header row to copy it; header sections show entry counts.
* Fix: flaky tests — `PeekyStore` is now enabled in test setup.
* Upgrade locked dependencies (`dio` 5.10.0) and `flutter_lints` to ^6.0.0.

## 0.0.4

* Add screenshots to README showcasing the inspector panel and response detail view.

## 0.0.3

* Fix: add missing `0.0.2` entry to CHANGELOG to satisfy pub.dev validation.

## 0.0.2

* Fix: shorten pubspec description to satisfy pub.dev length limit.
* Fix: add curly braces to all single-statement `if` blocks (lint compliance).

## 0.0.1

* Initial release.
* In-app network inspector for Flutter — supports `http` and Dio.
* Floating button and three-finger tap to open the inspector panel.
* Live request/response log with search, filtering, and cURL export.
* Captures Flutter framework errors in a dedicated Errors tab.
* Set `enabled: false` to make all instrumentation a no-op in production.
