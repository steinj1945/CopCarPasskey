import Foundation
import CoreBluetooth

enum BLEConstants {
    static let serviceUUID   = CBUUID(string: "6CEC9D24-598B-40CF-AA8F-A2BE12A626A6")
    static let challengeUUID = CBUUID(string: "FE879FA1-26CE-4CEB-AC6A-0FAE75D25E03")
    static let responseUUID  = CBUUID(string: "8EDE1ACC-39C6-4600-A06D-2D431C78ECB9")
    static let statusUUID    = CBUUID(string: "84962402-30AF-4AD3-A1AB-55696CFE1AB4")
}
