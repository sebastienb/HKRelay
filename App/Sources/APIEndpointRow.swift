import SwiftUI

struct APIEndpointRow: View {
    let method: String
    let path: String
    let description: String
    let curlExample: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(method)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(method == "PUT" ? Color.orange : Color.blue)
                    .frame(width: 34, alignment: .leading)

                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("curl example", systemImage: "terminal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = curlExample
                        copied = true
                    } label: {
                        Label(
                            copied ? "Copied" : "Copy",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .controlSize(.small)
                }

                ScrollView(.horizontal) {
                    Text(curlExample)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
    }
}

enum CurlExamples {
    static func health(baseURL: String) -> String {
        #"""
        curl --fail-with-body --silent --show-error \
          --header 'Accept: application/json' \
          '\#(baseURL)/health'
        """#
    }

    static func status(baseURL: String, authenticationRequired: Bool) -> String {
        get(path: "/v1/status", baseURL: baseURL, authenticationRequired: authenticationRequired)
    }

    static func accessories(baseURL: String, authenticationRequired: Bool) -> String {
        get(path: "/v1/accessories", baseURL: baseURL, authenticationRequired: authenticationRequired)
    }

    static func accessory(baseURL: String, authenticationRequired: Bool) -> String {
        get(
            path: "/v1/accessories/$ACCESSORY_ID",
            baseURL: baseURL,
            authenticationRequired: authenticationRequired
        )
    }

    static func readCharacteristic(baseURL: String, authenticationRequired: Bool) -> String {
        get(
            path: "/v1/accessories/$ACCESSORY_ID/characteristics/$CHARACTERISTIC_ID",
            baseURL: baseURL,
            authenticationRequired: authenticationRequired
        )
    }

    static func writeCharacteristic(baseURL: String, authenticationRequired: Bool) -> String {
        let authenticationHeader = authenticationRequired
            ? "header = \"Authorization: Bearer $HKBRIDGE_TOKEN\"\n"
            : ""
        return #"""
        curl --fail-with-body --silent --show-error --config - <<EOF
        url = "\#(baseURL)/v1/accessories/$ACCESSORY_ID/characteristics/$CHARACTERISTIC_ID"
        request = "PUT"
        \#(authenticationHeader)header = "Accept: application/json"
        header = "Content-Type: application/json"
        data = "{\"value\":true}"
        EOF
        """#
    }

    static func cameraMotion(baseURL: String, authenticationRequired: Bool) -> String {
        get(
            path: "/v1/accessories/$ACCESSORY_ID/camera/motion",
            baseURL: baseURL,
            authenticationRequired: authenticationRequired
        )
    }

    private static func get(path: String, baseURL: String, authenticationRequired: Bool) -> String {
        let authenticationHeader = authenticationRequired
            ? "header = \"Authorization: Bearer $HKBRIDGE_TOKEN\"\n"
            : ""
        return #"""
        curl --fail-with-body --silent --show-error --config - <<EOF
        url = "\#(baseURL)\#(path)"
        \#(authenticationHeader)header = "Accept: application/json"
        EOF
        """#
    }
}
