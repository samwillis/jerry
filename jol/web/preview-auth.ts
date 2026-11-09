// Imported only by the explicit local fixture build.
export function createAuthClient() {
  return {
    getSession: async () => ({
      data: {
        session: { token: "visual-fixture" },
        user: { id: "preview-user" },
      },
    }),
    signOut: async () => ({}),
  };
}
