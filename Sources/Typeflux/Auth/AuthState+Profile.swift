import Foundation

@MainActor
extension AuthState {
    // MARK: - Profile Refresh

    func refreshProfileIfNeeded() {
        guard isLoggedIn || accessToken != nil else { return }
        Task { await refreshProfile() }
    }

    @discardableResult
    func refreshProfile() async -> SessionRefreshResult {
        await refreshProfile(allowTokenRefresh: true)
    }

    @discardableResult
    private func refreshProfile(allowTokenRefresh: Bool) async -> SessionRefreshResult {
        guard let token = accessToken else {
            logger.error("Profile refresh found no valid access token; clearing session")
            logout()
            return .unauthenticated
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let profile = try await fetchProfile(token)
            userProfile = profile
            saveStoredUserProfile(profile)
            logger.info("Profile refreshed for \(profile.email)")
            await refreshSubscription()
            return .authenticated
        } catch let error as AuthError {
            if shouldInvalidateSession(for: error) {
                if allowTokenRefresh {
                    switch await refreshStoredAccessToken(force: true) {
                    case .refreshed:
                        return await refreshProfile(allowTokenRefresh: false)
                    case .failed:
                        logger.error("Profile refresh could not refresh access token: \(error.localizedDescription)")
                        return .failed
                    case .invalidated, .unavailable:
                        break
                    }
                }
                logout()
                logger.error("Profile refresh invalidated session: \(error.localizedDescription)")
                return .unauthenticated
            }
            logger.error("Failed to refresh profile: \(error.localizedDescription)")
            return .failed
        } catch {
            logger.error("Failed to refresh profile: \(error.localizedDescription)")
            return .failed
        }
    }
}
