import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/cast/dlna.dart';

const _desc = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>客厅电视</friendlyName>
    <modelName>Smart TV</modelName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/upnp/control/rc</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>upnp/control/avt</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';

void main() {
  test('设备描述：同时取到 AVTransport 和 RenderingControl 控制地址（顺序无关）', () {
    final d = Dlna.deviceFromDescription(_desc, location: 'http://192.168.1.9:49152/desc.xml', fallbackUdn: 'uuid:1');
    expect(d.name, '客厅电视');
    expect(d.controlUrl, 'http://192.168.1.9:49152/upnp/control/avt');
    expect(d.renderingUrl, 'http://192.168.1.9:49152/upnp/control/rc');
  });

  test('设备描述：没有 RenderingControl 时不能调音量，AVTransport:2 也认', () {
    final xml = _desc.replaceAll(RegExp(r'<service>\s*<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>\s*<controlURL>/upnp/control/rc</controlURL>\s*</service>'), '').replaceAll('AVTransport:1', 'AVTransport:2');
    final d = Dlna.deviceFromDescription(xml, location: 'http://192.168.1.9:49152/desc.xml', fallbackUdn: 'uuid:1');
    expect(d.controlUrl, 'http://192.168.1.9:49152/upnp/control/avt');
    expect(d.renderingUrl, isNull);
  });

  test('GetVolume 响应解析', () {
    expect(Dlna.parseVolume('<s:Envelope><s:Body><u:GetVolumeResponse><CurrentVolume>37</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>'), 37);
    expect(Dlna.parseVolume('<CurrentVolume>120</CurrentVolume>'), 100);
    expect(Dlna.parseVolume('<CurrentVolume></CurrentVolume>'), isNull);
    expect(Dlna.parseVolume('<Other>1</Other>'), isNull);
  });
}
