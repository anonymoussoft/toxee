# S110 — Contacts: Group-Notifications tab listing

**Layer**: L1 WidgetTester product-truth guard
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any groupApplications=not-mounted`
**Harness mode**: `test/ui/contact/contact_subtab_navigation_real_ui_test.dart` mounts the production Contacts surface.
**Promotion target**: DONE as a negative/absence gate. The requested tab is not part of toxee's production Contacts page.
**Status**: product truth verified 2026-06-10. The old spec was stale: toxee's real Contacts panel ships only **New Contacts** and **Blocked Users** in this surface. `contact_group_notifications_tab` and `TencentCloudChatContactGroupApplicationList` are not mounted by the production Contacts pane. A legacy anchor test can still fabricate a `ContactTabItem(id: 'group_notification')`, but that is not a shipped tab and must not be used as product evidence.
**Covered-by**: `test/ui/contact/contact_subtab_navigation_real_ui_test.dart`

## Precondition
- One account A can be logged in or mocked enough to mount Contacts.
- No live group invite fixture is required, because there is no production group-notification tab to populate.

## Assertions
- A1: the production Contacts pane renders `UiKeys.contactNewContactsTab`.
- A2: the production Contacts pane renders `UiKeys.contactBlockedUsersTab`.
- A3: `UiKeys.contactGroupNotificationsTab` is absent.
- A4: `TencentCloudChatContactGroupApplicationList` is absent.

## Notes
- This scenario is intentionally closed as a negative gate, not moved to an L3 live-invite playbook. Building a populated-list flow would first require product work to reintroduce a group-notification surface.
- Keep the fabricated `contact_application_anchors_test.dart` distinction clear: it proves a raw UIKit tab item can receive the old key when manually constructed; it does not prove the app mounts that tab.
