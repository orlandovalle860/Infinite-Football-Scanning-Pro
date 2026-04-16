//
//  PressureTriggerView.swift
//  FootballScanningAI
//
//  Use on iPhone: connect to iPad running Pressure Response (e.g. Playing Away from Pressure). Trigger via tap.
//

import SwiftUI

struct PressureTriggerView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject var multipeerManager: MultipeerManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            Text("Training Trigger")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Connect this iPhone to the iPad running an activity (e.g. Playing Away from Pressure), then tap to trigger (e.g. when you check to the passer, or when the pass is made).")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. On iPad: Start Training → choose activity (e.g. Playing Away from Pressure) → Start.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                Text("2. Keep iPhone and iPad nearby. Same Wi‑Fi is not required; they can connect over peer-to-peer. Allow Local Network if prompted.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                Text("3. Then tap Connect to iPad below.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal)

            if let error = connectionManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
            }

            if connectionManager.connectedPeerName != nil {
                Text("Connected to \(connectionManager.connectedPeerName!)")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                Text("Not connected")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            if !connectionManager.isBrowsing {
                Button("Connect to iPad") {
                    connectionManager.lastError = nil
                    connectionManager.startBrowsing()
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            } else if connectionManager.connectedPeerName == nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                Text("Searching for iPad…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Button("Cancel") {
                    connectionManager.stopBrowsing()
                }
                .foregroundColor(.white.opacity(0.9))
            }

            if connectionManager.connectedPeerName != nil {
                Text("Tap below to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Button(action: {
                    connectionManager.lastError = nil
                    connectionManager.sendTrigger()
                }) {
                    Text("Pass Made")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.green)
                        .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 8)

                Button(action: {
                    connectionManager.lastError = nil
                }) {
                    Text("Clear error")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    connectionManager.stopBrowsing()
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .onDisappear {
            connectionManager.stopBrowsing()
        }
    }
}
