// Package fixture is a small module for the lint-go and coverage actions' tests.
package fixture

// Greet greets name, or the world without one.
func Greet(name string) string {
	if name == "" {
		return "Hello, world"
	}
	return "Hello, " + name
}
