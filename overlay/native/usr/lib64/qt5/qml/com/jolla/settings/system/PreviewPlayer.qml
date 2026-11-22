import QtQuick 2.0
import QtMultimedia 5.0
import org.nemomobile.systemsettings 1.0

Audio {
    id: previewPlayer

    // Native preview streams have no ringtone role for the policy engine.
    // Match the profile's PulseAudio cubic volume scale explicitly.
    property QtObject nabuProfile: ProfileControl {}
    volume: Math.pow(Math.max(0, Math.min(1, nabuProfile.ringerVolume / 100)), 3)
    muted: nabuProfile.profile === "silent" || nabuProfile.ringerVolume === 0

    property string title

    function toggle(source) {
        if (playbackState == Audio.PlayingState || source == "") {
            stop()
        } else {
            play()
        }
    }

    onStatusChanged: {
        if (status == Audio.Loaded) {
            title = metaData.title ? metaData.title : ""
        }
    }
}
