import XCTest
@testable import MacMuleCore

final class UPnPPortMapperTests: XCTestCase {
    func testDescriptionParserExtractsWANIPConnectionControlURL() throws {
        let xml = """
        <?xml version="1.0"?>
        <root>
          <URLBase>http://192.168.1.1:1900/</URLBase>
          <device>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
                <controlURL>/upnp/control/commonifc1</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
                <controlURL>/upnp/control/WANIPConn1</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """

        let parser = UPnPDeviceDescriptionParser()
        let service = try parser.parse(
            data: Data(xml.utf8),
            descriptionURL: URL(string: "http://192.168.1.1:1900/rootDesc.xml")!
        )

        XCTAssertEqual(service?.serviceType, "urn:schemas-upnp-org:service:WANIPConnection:1")
        XCTAssertEqual(service?.controlURL, URL(string: "http://192.168.1.1:1900/upnp/control/WANIPConn1"))
    }

    func testDescriptionParserFallsBackToDescriptionURLForRelativeControlURL() throws {
        let xml = """
        <?xml version="1.0"?>
        <root>
          <device>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType>
                <controlURL>control?WANPPPConnection</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """

        let parser = UPnPDeviceDescriptionParser()
        let service = try parser.parse(
            data: Data(xml.utf8),
            descriptionURL: URL(string: "http://192.168.0.1:5431/igd.xml")!
        )

        XCTAssertEqual(service?.serviceType, "urn:schemas-upnp-org:service:WANPPPConnection:1")
        XCTAssertEqual(service?.controlURL, URL(string: "http://192.168.0.1:5431/control?WANPPPConnection"))
    }
}
