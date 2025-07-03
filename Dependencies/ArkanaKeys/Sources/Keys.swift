import Foundation

public struct Keys {
    
    public struct Debug {
        public let notificationEndpoint: String = "https://debug.notifications.example.com"
        
        public init() {}
    }
    
    public struct Release {
        public let notificationEndpoint: String = "https://notifications.example.com"
        
        public init() {}
    }
}