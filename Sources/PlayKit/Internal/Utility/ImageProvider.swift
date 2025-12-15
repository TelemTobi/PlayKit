//
//  ImageProvider.swift
//  PlayKit
//
//  Created by Telem Tobi on 06/11/2025.
//

import Foundation
import UIKit

final actor ImageProvider {
    static let shared = ImageProvider()
    
    private let cache = NSCache<AnyObject, UIImage>()
    
    private init() {
        cache.countLimit = 10
//        cache.totalCostLimit = 100_000_000
    }

    @discardableResult
    func loadImage(from url: URL) async -> UIImage? {
        if let cachedImage = cache.object(forKey: url as AnyObject) {
            return cachedImage
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let imageToCache = UIImage(data: data) else { return nil }
            
            cache.setObject(imageToCache, forKey: url as AnyObject)
            return imageToCache
            
        } catch {
            return nil
        }
    }
}
