describe('My First Test', () => {
  it('Visits the app root url', () => {
    cy.visit('/')
    cy.contains('Push works only in the Android app')
  })
})
