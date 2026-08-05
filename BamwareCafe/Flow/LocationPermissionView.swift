import SwiftUI

struct LocationPermissionView: View {
    let locationService: LocationService
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            AppBrand.pageGradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(AppBrand.moss.opacity(0.14))
                        .frame(width: 230, height: 230)
                    Image(systemName: "location.fill.viewfinder")
                        .font(.system(size: 92, weight: .light))
                        .foregroundStyle(AppBrand.moss)
                }
                VStack(spacing: 12) {
                    Text("Start where you are.")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(AppBrand.espresso)
                    Text("Your location finds cafes nearby. It is never included in a public report.")
                        .font(.title3)
                        .foregroundStyle(AppBrand.muted)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button("Use my location") {
                    locationService.requestAccess()
                    onComplete()
                }
                .buttonStyle(PrimaryActionStyle())
                Button("Use Union Square instead") { onComplete() }
                    .font(.subheadline.bold())
                    .foregroundStyle(AppBrand.muted)
            }
            .padding(24)
        }
    }
}
