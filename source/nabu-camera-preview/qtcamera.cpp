// SPDX-License-Identifier: LGPL-2.1-or-later
#include <QtCore/QString>
#include <QtCore/QByteArray>
#include <QtCore/QVector>
#include <QtCore/QList>
#include <QtMultimedia/QCamera>
struct _GstElementFactory;
typedef struct _GstElementFactory GstElementFactory;
namespace QGstUtils {
// Qt 5.6 gsttools camera descriptor layout.
struct CameraInfo {
    QString name;
    QString description;
    int orientation;
    QCamera::Position position;
    QByteArray driver;
};
QVector<CameraInfo> enumerateCameras(GstElementFactory *)
{
    QVector<CameraInfo> cameras;
    cameras.append({QString::fromLatin1("nabu-front"), QString::fromLatin1("Front camera"),
                    270, QCamera::FrontFace, QByteArray("nabu-native")});
    cameras.append({QString::fromLatin1("nabu-rear"), QString::fromLatin1("Rear camera"),
                    270, QCamera::BackFace, QByteArray("nabu-native")});
    return cameras;
}
QList<QByteArray> cameraDevices(GstElementFactory *factory)
{
    QList<QByteArray> names;
    for (const auto &camera : enumerateCameras(factory)) names.append(camera.name.toUtf8());
    return names;
}
QString cameraDescription(const QString &name, GstElementFactory *factory)
{
    for (const auto &camera : enumerateCameras(factory))
        if (camera.name == name) return camera.description;
    return QString();
}
QCamera::Position cameraPosition(const QString &name, GstElementFactory *)
{
    return name == QString::fromLatin1("nabu-front") ? QCamera::FrontFace :
           name == QString::fromLatin1("nabu-rear") ? QCamera::BackFace : QCamera::UnspecifiedPosition;
}
int cameraOrientation(const QString &, GstElementFactory *) { return 270; }
QByteArray cameraDriver(const QString &, GstElementFactory *) { return QByteArray("nabu-native"); }
}
