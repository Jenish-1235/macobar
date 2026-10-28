import Contacts
import Foundation

/// Looks people up in the user's Contacts.
struct FindContactTool: Tool {
    /// Name the model calls it by.
    let name = "find_contact"
    /// When to use it and what it returns.
    let description = """
        Searches Contacts by name for emails, phones and organization. Call it before emailing or messaging someone \
        by name.
        """

    /// The name to search for.
    var parameters: JSONValue {
        Schema.object(["name": Schema.string("All or part of a name.")], required: ["name"])
    }

    /// Its result carries contact cards, which can come from other people's vCards.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String {
        "Looking up \(input.string("name") ?? "a contact") in Contacts"
    }

    /// Finds and formats the matching contacts.
    func run(_ input: ToolInput) async throws -> String {
        let name = try input.requiredString("name")
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else {
            throw ToolError("macobar can't access Contacts. Ask the user to allow macobar in System Settings → Privacy & Security → Contacts, then try again.")
        }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        guard !contacts.isEmpty else { return "No contacts match “\(name)”." }
        return contacts.prefix(10).map(summary).joined(separator: "\n")
    }

    /// The contact's name and organization, then one indented line per email and phone.
    private func summary(of contact: CNContact) -> String {
        var lines = [CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName]
        if !contact.organizationName.isEmpty, lines[0] != contact.organizationName { lines[0] += " (\(contact.organizationName))" }
        lines += contact.emailAddresses.map { "  email \(labelText($0.label)): \($0.value as String)" }
        lines += contact.phoneNumbers.map { "  phone \(labelText($0.label)): \($0.value.stringValue)" }
        return lines.joined(separator: "\n")
    }

    /// The localized name of a contact field label such as "home" or "mobile".
    private func labelText(_ label: String?) -> String {
        label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "other"
    }
}
