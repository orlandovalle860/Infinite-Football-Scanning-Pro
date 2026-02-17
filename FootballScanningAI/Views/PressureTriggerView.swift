//
//  PressureTriggerView.swift
//  FootballScanningAI
//
//  Use on iPhone: connect to iPad running Pressure Response, then tap to trigger the defender.
//

import SwiftUI

struct PressureTriggerView: View {
    @EnvironmentObject var multipeerManager: MultipeerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Pressure Response Trigger")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Connect this iPhone to the iPad running Playing Away from Pressure, then tap when you check to the passer.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = multipeerManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
            }

            if multipeerManager.connectedPeerName != nil {
                Text("Connected to \(multipeerManager.connectedPeerName!)")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                Text("Not connected")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            if !multipeerManager.isBrowsing {
                Button("Connect to iPad") {
                    multipeerManager.lastError = nil
                    multipeerManager.startBrowsing()
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            } else if multipeerManager.connectedPeerName == nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                Text("Searching for iPad…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Button("Cancel") {
                    multipeerManager.stopBrowsing()
                }
                .foregroundColor(.white.opacity(0.9))
            }

            if multipeerManager.connectedPeerName != nil {
                Button(action: {
                    multipeerManager.lastError = nil
                    multipeerManager.sendTrigger()
                }) {
                    Text("TRIGGER")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.green)
                        .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    multipeerManager.stopBrowsing()
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .onDisappear {
            multipeerManager.stopBrowsing()
        }
    }
}
