// Runs on every Jenkins start. Creating the admin account here keeps the
// credential out of the setup wizard, which is disabled for this instance.
import jenkins.model.Jenkins
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.get()

def adminUser = System.getenv('JENKINS_ADMIN_ID') ?: 'admin'
def adminPassword = System.getenv('JENKINS_ADMIN_PASSWORD')

if (!adminPassword) {
    println '--> JENKINS_ADMIN_PASSWORD not set; leaving security untouched.'
    return
}

if (!(instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
    def realm = new HudsonPrivateSecurityRealm(false)
    realm.createAccount(adminUser, adminPassword)
    instance.setSecurityRealm(realm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)

    instance.save()
    println "--> Created Jenkins admin user '${adminUser}'."
} else {
    println '--> Security realm already configured; no changes made.'
}
