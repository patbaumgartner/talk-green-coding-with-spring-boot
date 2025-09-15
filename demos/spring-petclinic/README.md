# Notes to Execute the JoularJX Spring Petclinic Benchmark

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
java -jar target/spring-petclinic-3.5.0-SNAPSHOT.jar
```

**On a PowerShell shell:**

```bash
java -jar .\target\spring-petclinic-3.5.0-SNAPSHOT.jar
```

---

## ⚡ Run the Application With Benchmarking

**On a bash shell:**

```bash
java -javaagent:joularjx-3.0.1.jar -Djoularjx.config=config.properties -jar target/spring-petclinic-3.5.0-SNAPSHOT.jar
```

**On a PowerShell shell:**

```bash
java -javaagent:joularjx-3.0.1.jar "-Djoularjx.config=.\config.properties" -jar .\target\spring-petclinic-3.5.0-SNAPSHOT.jar
```

The output will be printed to the console:

```console
17/09/2025 07:14:11.886 - [INFO] - +---------------------------------+
17/09/2025 07:14:11.887 - [INFO] - | JoularJX Agent Version 3.0.1    |
17/09/2025 07:14:11.887 - [INFO] - +---------------------------------+
17/09/2025 07:14:11.901 - [INFO] - Results will be stored in joularjx-result/39440-1758129251900/
17/09/2025 07:14:11.923 - [INFO] - Initializing for platform: 'windows 11' running on architecture: 'amd64'
17/09/2025 07:14:11.927 - [INFO] - Please wait while initializing JoularJX...
17/09/2025 07:14:13.714 - [INFO] - Initialization finished
17/09/2025 07:14:13.715 - [INFO] - Started monitoring application with ID 39440


              |\      _,,,--,,_
             /,`.-'`'   ._  \-;;,_
  _______ __|,4-  ) )_   .;.(__`'-'__     ___ __    _ ___ _______
 |       | '---''(_/._)-'(_\_)   |   |   |   |  |  | |   |       |
 |    _  |    ___|_     _|       |   |   |   |   |_| |   |       | __ _ _
 |   |_| |   |___  |   | |       |   |   |   |       |   |       | \ \ \ \
 |    ___|    ___| |   | |      _|   |___|   |  _    |   |      _|  \ \ \ \
 |   |   |   |___  |   | |     |_|       |   | | |   |   |     |_    ) ) ) )
 |___|   |_______| |___| |_______|_______|___|_|  |__|___|_______|  / / / /
 ==================================================================/_/_/_/

:: Built with Spring Boot :: 3.5.5


2025-09-17T19:14:16.806+02:00  INFO 39440 --- [JX Agent Thread] o.s.s.petclinic.PetClinicApplication     : Starting PetClinicApplication v3.5.0-SNAPSHOT using Java 21.0.8 with PID 39440 (C:\Users\patbaumgartner\OneDrive\Desktop\spring-petclinic\target\spring-petclinic-3.5.0-SNAPSHOT.jar started by patbaumgartner in C:\Users\patbaumgartner\OneDrive\Desktop\spring-petclinic)
2025-09-17T19:14:16.818+02:00  INFO 39440 --- [JX Agent Thread] o.s.s.petclinic.PetClinicApplication     : No active profile set, falling back to 1 default profile: "default"
2025-09-17T19:14:20.611+02:00  INFO 39440 --- [JX Agent Thread] .s.d.r.c.RepositoryConfigurationDelegate : Bootstrapping Spring Data JPA repositories in DEFAULT mode.
2025-09-17T19:14:20.855+02:00  INFO 39440 --- [JX Agent Thread] .s.d.r.c.RepositoryConfigurationDelegate : Finished Spring Data repository scanning in 208 ms. Found 3 JPA repository interfaces.
17/09/2025 07:14:21.191 - [INFO] - Thread CPU time negative, taking previous time + 0 : 375000000 for thread: 45
17/09/2025 07:14:21.192 - [INFO] - Thread CPU time negative, taking previous time + 0 : 0 for thread: 48
2025-09-17T19:14:23.484+02:00  INFO 39440 --- [JX Agent Thread] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8080 (http)
2025-09-17T19:14:23.548+02:00  INFO 39440 --- [JX Agent Thread] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
2025-09-17T19:14:23.549+02:00  INFO 39440 --- [JX Agent Thread] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.44]
2025-09-17T19:14:23.672+02:00  INFO 39440 --- [JX Agent Thread] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
2025-09-17T19:14:23.674+02:00  INFO 39440 --- [JX Agent Thread] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 6691 ms
2025-09-17T19:14:24.861+02:00  INFO 39440 --- [JX Agent Thread] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Starting...
2025-09-17T19:14:25.663+02:00  INFO 39440 --- [JX Agent Thread] com.zaxxer.hikari.pool.HikariPool        : HikariPool-1 - Added connection conn0: url=jdbc:h2:mem:a47e9013-71eb-4619-89df-c2fa2371215a user=SA
2025-09-17T19:14:25.668+02:00  INFO 39440 --- [JX Agent Thread] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Start completed.
2025-09-17T19:14:26.230+02:00  INFO 39440 --- [JX Agent Thread] o.hibernate.jpa.internal.util.LogHelper  : HHH000204: Processing PersistenceUnitInfo [name: default]
2025-09-17T19:14:26.629+02:00  INFO 39440 --- [JX Agent Thread] org.hibernate.Version                    : HHH000412: Hibernate ORM core version 6.6.26.Final
2025-09-17T19:14:26.747+02:00  INFO 39440 --- [JX Agent Thread] o.h.c.internal.RegionFactoryInitiator    : HHH000026: Second-level cache disabled
2025-09-17T19:14:27.315+02:00  INFO 39440 --- [JX Agent Thread] o.s.o.j.p.SpringPersistenceUnitInfo      : No LoadTimeWeaver setup: ignoring JPA class transformer
2025-09-17T19:14:27.562+02:00  INFO 39440 --- [JX Agent Thread] org.hibernate.orm.connections.pooling    : HHH10001005: Database info:
        Database JDBC URL [Connecting through datasource 'HikariDataSource (HikariPool-1)']
        Database driver: undefined/unknown
        Database version: 2.3.232
        Autocommit mode: undefined/unknown
        Isolation level: undefined/unknown
        Minimum pool size: undefined/unknown
        Maximum pool size: undefined/unknown
2025-09-17T19:14:30.231+02:00  INFO 39440 --- [JX Agent Thread] o.h.e.t.j.p.i.JtaPlatformInitiator       : HHH000489: No JTA platform available (set 'hibernate.transaction.jta.platform' to enable JTA platform integration)
2025-09-17T19:14:30.239+02:00  INFO 39440 --- [JX Agent Thread] j.LocalContainerEntityManagerFactoryBean : Initialized JPA EntityManagerFactory for persistence unit 'default'
2025-09-17T19:14:31.536+02:00  INFO 39440 --- [JX Agent Thread] o.s.d.j.r.query.QueryEnhancerFactory     : Hibernate is in classpath; If applicable, HQL parser will be used.
2025-09-17T19:14:35.683+02:00  INFO 39440 --- [JX Agent Thread] o.s.b.a.e.web.EndpointLinksResolver      : Exposing 13 endpoints beneath base path '/actuator'
2025-09-17T19:14:35.962+02:00  INFO 39440 --- [JX Agent Thread] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path '/'
2025-09-17T19:14:36.004+02:00  INFO 39440 --- [JX Agent Thread] o.s.s.petclinic.PetClinicApplication     : Started PetClinicApplication in 20.544 seconds (process running for 24.244)
```

---

## ⚡ Run the jMeter Tests in a Separate Terminal

Execute the following command:

```bash
mvn jmeter:configure@configuration jmeter:jmeter@configuration
```

---

## 🛑 Stop the Application After Tests

Once the tests are finished, stop the Spring Boot application with:

```text
Ctrl+C
```
