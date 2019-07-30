//
//  PeerToPeer.swift
//  VowLink
//
//  Created by Indutnyy, Fedor on 7/28/19.
//  Copyright © 2019 Indutnyy, Fedor. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import KeychainAccess
import Sodium

protocol PeerToPeerDelegate {
    func peerToPeer(_ p2p: PeerToPeer, didReceive packet: Proto_Packet, fromPeer peer: Peer)
}

class PeerToPeer: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    let context: Context
    let peer: MCPeerID
    let advertiser: MCNearbyServiceAdvertiser
    let browser: MCNearbyServiceBrowser
    let session: MCSession
    var delegate: PeerToPeerDelegate?
    var peers = [MCPeerID:Peer]()
    
    init(context: Context, serviceType: String) {
        self.context = context
        
        let defaults = UserDefaults.standard
        if let raw_peer = defaults.data(forKey: "peer-id") {
            peer = try! NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: raw_peer)!
        } else {
            peer = MCPeerID(displayName: NSUUID().uuidString)
            let data = try! NSKeyedArchiver.archivedData(withRootObject: peer as Any,
                                                         requiringSecureCoding: true)
            defaults.set(data, forKey: "peer-id")
            defaults.synchronize()
        }
        
        debugPrint("[p2p] start peer.displayName=\(peer.displayName)")
        
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: serviceType)
        advertiser.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        browser.startBrowsingForPeers()
        
        super.init()
        
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }
    
    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
    }
    
    // MARK: Public API

    // MARK: Advertiser
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        debugPrint("[advertiser] did not start due to error \(error), retrying...")
        advertiser.startAdvertisingPeer()
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if peers[peerID] != nil || peerID == self.peer {
            debugPrint("[advertiser] declining invitation from \(peerID.displayName)")
            invitationHandler(false, session)
            return
        }
        
        debugPrint("[advertiser] accepting invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    // MARK: Browser
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        debugPrint("[browser] lost peer \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        debugPrint("[browser] did not start due to error \(error), retrying...")
        browser.startBrowsingForPeers()
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        debugPrint("[browser] found peer \(peerID.displayName) with info \(String(describing: info))")
        if peers[peerID] != nil || peerID == self.peer {
            debugPrint("[browser] ignoring peer \(peerID.displayName)")
            return
        }
        
        if peerID.displayName > peer.displayName {
            debugPrint("[browser] inviting peer \(peerID.displayName) into session")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 300.0)
        }
    }
    
    // MARK: Session
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        debugPrint("[session] received from \(peerID.displayName) data \(data)")
        guard let peer = peers[peerID] else {
            debugPrint("[session] unknown peer...")
            return
        }

        do {
            guard let packet = try peer.receivePacket(data: data) else {
                debugPrint("[session] reached rate limit or hello packet")
                return
            }
        
            debugPrint("[session] packet \(packet)")
            
            delegate?.peerToPeer(self, didReceive: packet, fromPeer: peer)
        } catch  {
            debugPrint("[session] parsing error \(error)")
        }
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connecting:
            debugPrint("[session] connecting to \(peerID.displayName)")
            return
        case .notConnected:
            peers.removeValue(forKey: peerID)
            debugPrint("[session] disconnected from \(peerID.displayName)")
            return
        case .connected:
            debugPrint("[session] connected to \(peerID.displayName)")
            break
        default:
            debugPrint("[session] unknown state transition for \(peerID.displayName)")
            return
        }
        let peer = Peer(context: context, session: session, peerID: peerID)
        do {
            try peer.sendHello()
            peers[peerID] = peer
        } catch {
            debugPrint("[session] failed to send hello to \(peerID.displayName) due to error \(error)")
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        debugPrint("[session] received from \(peerID.displayName) stream, closing immediately")
        stream.close()
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        debugPrint("[session] received from \(peerID.displayName) resource \(resourceName), cancelling")
        progress.cancel()
    }
    
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        debugPrint("[session] received from \(peerID.displayName) certificates \(String(describing: certificate))")
        certificateHandler(true)
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        debugPrint("[session] finished receiving from \(peerID.displayName) resource \(resourceName)")
    }
}
