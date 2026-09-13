import QtQuick

// A stand-in `bar` for the hover preview only.
//
// PopupCard.onOpenChanged calls bar.requestPopout() unconditionally, and
// Bar.requestPopout closes whatever popout is currently open. For a click
// popup that is correct -- one panel at a time. For a *hover* preview it is
// not: merely sweeping the pointer along the taskbar would slam shut an open
// clock calendar or audio panel without the user ever clicking anything.
//
// PopupCard only ever touches four things on `bar` (verified by reading it:
// position, requestPopout, releasePopout, activePopout), so mirroring the one
// it needs for layout and making the other three inert is enough. The context
// menu keeps the real bar, where taking the popout slot is the desired
// behavior.
QtObject {
  id: shim

  property var source: null

  readonly property string position: shim.source ? shim.source.position : "top"
  readonly property bool vertical: shim.source ? shim.source.vertical : false
  readonly property int barSize: shim.source ? shim.source.barSize : 26

  // Never set. PopupCard compares activePopout against its own coordinatorKey
  // and only calls releasePopout on a match, so leaving this null makes both
  // sides of that branch no-ops.
  property var activePopout: null

  function requestPopout(owner) {}
  function releasePopout(owner) {}
}
