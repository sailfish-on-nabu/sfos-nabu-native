import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

Column {
    id: root
    width: parent.width

    ConfigurationValue {
        id: preference
        key: "/desktop/nabu/display/refresh_rate"
        defaultValue: 120
        onValueChanged: selector.currentIndex = value === 60 ? 0 : 1
    }

    ConfigurationValue {
        id: applyError
        key: "/desktop/nabu/display/refresh_rate_error"
        defaultValue: ""
    }

    ComboBox {
        id: selector
        width: parent.width
        label: qsTr("屏幕刷新率")
        Component.onCompleted: currentIndex = preference.value === 60 ? 0 : 1
        menu: ContextMenu {
            MenuItem {
                text: "60 Hz"
                onDelayedClick: preference.value = 60
            }
            MenuItem {
                text: "120 Hz"
                onDelayedClick: preference.value = 120
            }
        }
    }

    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * x
        font.pixelSize: Theme.fontSizeExtraSmall
        color: applyError.value ? Theme.errorColor : Theme.secondaryColor
        wrapMode: Text.Wrap
        text: applyError.value
              ? qsTr("刷新率暂未应用，亮屏后将自动重试。")
              : qsTr("60 Hz 更省电，120 Hz 更流畅。选择会自动保存。")
    }
}
