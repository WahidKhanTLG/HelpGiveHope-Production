/**
 * Existing-record lookup only: require nine digits, optionally with dashes.
 * Historical/test records may contain reserved groups. Allow the lookup without
 * treating the value as a verified/issued SSN. New-value server rules are separate.
 * Never log or persist the entered value in browser storage.
 */
export function validateLookupSsn(value) {
  const input = String(value ?? "").trim();
  if (!input) return "Please enter your SSN.";
  if (!/^(?:[0-9]{9}|[0-9]{3}-[0-9]{2}-[0-9]{4})$/.test(input)) {
    return "Please enter all 9 digits of your SSN.";
  }
  return "";
}
export function normalizeSsn(value) {
  return String(value ?? "").trim().replaceAll("-", "");
}
export function renumberMembers(members, role) {
  return members.map((member, index) => ({ ...member, title: `${role} ${index + 1}` }));
}
export function memberIdentityKey(section) {
  const field = (name) => String(section?.fieldsMap?.[name]?.value ?? "").trim().toLowerCase().replace(/\s+/g, " ");
  return [field("FirstName"), field("LastName"), field("DateOfBirth")].join("|");
}
export function memberSsnKey(section) {
  if (!section || section.storedSsn === true) return "";
  const value = section?.fieldsMap?.SSN?.value;
  const normalized = normalizeSsn(value);
  return /^\d{9}$/.test(normalized) ? normalized : "";
}
export function prefillValues(member) {
  return {
    FirstName: member?.firstName || "",
    LastName: member?.lastName || "",
    EmailAddress: member?.email || "",
    DateOfBirth: member?.birthDate || "",
    Gender: member?.gender || "",
    Phone: member?.phone || "",
    SSN: member?.ssn || ""
  };
}
export function ageOnDate(isoDate, today = new Date()) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(isoDate || "")) return "";
  const [y, m, d] = isoDate.split("-").map(Number);
  const birth = new Date(y, m - 1, d);
  if (birth.getFullYear() !== y || birth.getMonth() !== m - 1 || birth.getDate() !== d) return "";
  let age = today.getFullYear() - y;
  if (today.getMonth() < m - 1 || (today.getMonth() === m - 1 && today.getDate() < d)) age -= 1;
  return age < 0 ? "" : String(age);
}