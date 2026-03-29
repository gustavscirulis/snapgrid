import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var fileSystem: FileSystemManager

    var body: some View {
        ZStack {
            Color.snapDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "icloud")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("SnapGrid")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("Sign in to iCloud to sync\nyour SnapGrid library")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "gear")
                                .font(.body.weight(.medium))
                            Text("Open Settings")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    Button {
                        fileSystem.restoreAccess()
                    } label: {
                        Text("Try Again")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .padding(.horizontal, 24)

                    if let error = fileSystem.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer()
                    .frame(height: 40)
            }
        }
    }
}
