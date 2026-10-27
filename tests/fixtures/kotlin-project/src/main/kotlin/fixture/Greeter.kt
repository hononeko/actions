package fixture

/** Greets [name], or the world without one. */
fun greet(name: String?): String = if (name.isNullOrEmpty()) "Hello, world" else "Hello, $name"
