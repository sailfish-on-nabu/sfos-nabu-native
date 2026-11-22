// SPDX-FileCopyrightText: 2026 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.6
import QtMultimedia 5.0
import com.jolla.camera 1.0
import Sailfish.Media 1.0
import Sailfish.Silica 1.0

VideoOutput {
    id: viewfinder

    property real uiRotation

    readonly property bool nativeCamera: source && source.deviceId
                                         && source.deviceId.indexOf("nabu-") === 0
    // This viewfinder stays in the unrotated window, outside the camera page.
    // Compensate only for the physical sensor mount, once.
    // The front-facing sensor has the opposite viewing direction. Its
    // landscape compensation is reversed relative to the fixed window.
    orientation: nativeCamera ? (source.orientation
                                 + (source.position === Camera.FrontFace ? 2 * uiRotation : 0)
                                 + 720) % 360 : 0
    fillMode: nativeCamera ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit

    readonly property DisplayStream displayStream: DisplayStream {}
    readonly property PreviewStreamFilter streamFilter: PreviewStreamFilter {
        stream: viewfinder.displayStream
        // The camera backend supplies a GL_TEXTURE_EXTERNAL_OES handle.
        externalTexture: true
        active: viewfinder.displayStream.state === DisplayStream.Streaming
    }

    // The video backend draws the frame fitted whatever the fill mode, so on a small screen the
    // viewfinder is scaled up to cover the item, cropping the frame's edges.
    readonly property real fillScale: !nativeCamera && Settings.fillViewfinder && contentRect.width > 0 && contentRect.height > 0
                                      ? Math.max(width / contentRect.width, height / contentRect.height)
                                      : 1

    // Keep the video node rendering while showing controls over a black background.
    Rectangle {
        parent: viewfinder.parent
        anchors.fill: parent
        z: viewfinder.z + 0.5
        color: "black"
        visible: viewfinder.displayStream.state === DisplayStream.Streaming

        Label {
            anchors.centerIn: parent
            rotation: viewfinder.uiRotation
            width: Math.max(0, Math.min(parent.width, parent.height)
                            - 2 * (Theme.itemSizeMedium + Theme.paddingLarge))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            //% "Viewfinder is on the alternative display"
            text: qsTrId("camera-la-alternative_display_viewfinder")
            color: Theme.lightPrimaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    transform: Scale {
        origin.x: viewfinder.width / 2
        origin.y: viewfinder.height / 2
        xScale: viewfinder.fillScale
        yScale: viewfinder.fillScale
    }
}
