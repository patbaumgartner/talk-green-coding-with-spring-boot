# Notes to Execute the JoularJX Benchmark

## 🔨 Build the Project

Build the project with Maven:

```bash
mvn clean verify
```

The generated artifact will be located in the `target` folder.

---

## ▶️ Run the Application Without Benchmarking

**On a bash shell:**

```bash
java -jar target/joularjx-benchmark-1.0-SNAPSHOT.jar
```

**On a PowerShell shell:**

```bash
java -jar .\target\joularjx-benchmark-1.0-SNAPSHOT.jar
```

The output will be printed to the console:

```console
Number of primes between 2 and 100000000: 5761455
Time taken: 39226 ms
```

---

## ⚡ Run the Application With Benchmarking

**On a bash shell:**

```bash
java -javaagent:joularjx-3.0.1.jar -Djoularjx.config=config.properties -jar target/joularjx-benchmark-1.0-SNAPSHOT.jar
```

**On a PowerShell shell:**

```bash
java -javaagent:joularjx-3.0.1.jar "-Djoularjx.config=.\config.properties" -jar .\target\joularjx-benchmark-1.0-SNAPSHOT.jar
```

The output will be printed to the console:

```console
17/09/2025 05:45:53.123 - [INFO] - +---------------------------------+
17/09/2025 05:45:53.123 - [INFO] - | JoularJX Agent Version 3.0.1    |
17/09/2025 05:45:53.123 - [INFO] - +---------------------------------+
17/09/2025 05:45:53.260 - [INFO] - Results will be stored in joularjx-result/10740-1758123953258/
17/09/2025 05:45:53.280 - [INFO] - Initializing for platform: 'windows 11' running on architecture: 'amd64'
17/09/2025 05:45:53.281 - [INFO] - Please wait while initializing JoularJX...
17/09/2025 05:45:54.778 - [INFO] - Initialization finished
17/09/2025 05:45:54.780 - [INFO] - Started monitoring application with ID 10740
Number of primes between 2 and 100000000: 5761455
Time taken: 41491 ms
17/09/2025 05:46:37.499 - [INFO] - Thread CPU time negative, taking previous time + 1 : 41281250001 for thread: 1
17/09/2025 05:46:37.524 - [INFO] - JoularJX finished monitoring application with ID 10740
17/09/2025 05:46:37.525 - [INFO] - Program consumed 160.43 joules
17/09/2025 05:46:37.542 - [INFO] - Energy consumption of methods and filtered methods written to files
```
