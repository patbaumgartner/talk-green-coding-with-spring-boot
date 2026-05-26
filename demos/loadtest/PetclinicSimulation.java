import io.gatling.javaapi.core.*;
import io.gatling.javaapi.http.*;

import java.time.Duration;
import java.util.List;
import java.util.Map;

import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

/**
 * Gatling load test for Spring Petclinic.
 *
 * Mirrors the scenario in petclinic_test_plan.jmx:
 * - Same 13-request URL sequence (home → CSS → JS → vets → owners → edit → pet
 * → visit)
 * - 300 ms pause between requests (JMeter ConstantTimer)
 * - Owner/pet IDs cycle 1–3 (JMeter CounterConfig)
 * - Cookies are per virtual user and reset between users (JMeter CookieManager)
 *
 * Configuration via JVM system properties (pass via JAVA_OPTS="-Dkey=value"):
 * baseUrl — base URL of the target app (default: http://localhost:8080)
 * users — peak concurrent users (default: 10)
 * rampSeconds — ramp-up duration in seconds (default: 10)
 * durationSeconds — steady-state duration in secs (default: 60)
 *
 * Example:
 * JAVA_OPTS="-DbaseUrl=http://localhost:9090 -Dusers=20 -DdurationSeconds=120"
 * \
 * $GATLING_HOME/bin/gatling.sh -sf demos/loadtest -s PetclinicSimulation
 */
public class PetclinicSimulation extends Simulation {

        private static final String BASE_URL = System.getProperty("baseUrl", "http://localhost:8080");
        private static final int USERS = Integer.parseInt(System.getProperty("users", "10"));
        private static final long RAMP_SECONDS = Long.parseLong(System.getProperty("rampSeconds", "10"));
        private static final long DURATION_SECONDS = Long.parseLong(System.getProperty("durationSeconds", "60"));

        // Cycling feeder: owner IDs 1–3 paired with pet IDs 1–3
        // Mirrors the two JMeter CounterConfig elements (count and petCount, range
        // 1–3).
        private static final List<Map<String, Object>> COUNTER_DATA = List.of(
                        Map.of("count", "1", "petCount", "1"),
                        Map.of("count", "2", "petCount", "2"),
                        Map.of("count", "3", "petCount", "3"));

        private final FeederBuilder<Object> counterFeeder = listFeeder(COUNTER_DATA).circular();

        private final HttpProtocolBuilder httpProtocol = http
                        .baseUrl(BASE_URL)
                        .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                        .acceptEncodingHeader("gzip, deflate")
                        .userAgentHeader("Gatling/PetclinicLoadTest");

        private final ScenarioBuilder scn = scenario("Petclinic User Journey")
                        .feed(counterFeeder)
                        // 1. Home page
                        .exec(http("Home page").get("/"))
                        .pause(Duration.ofMillis(300))
                        // 2. CSS
                        .exec(http("CSS").get("/resources/css/petclinic.css"))
                        .pause(Duration.ofMillis(300))
                        // 3. Bootstrap JS
                        .exec(http("Bootstrap JS").get("/webjars/bootstrap/dist/js/bootstrap.bundle.min.js"))
                        .pause(Duration.ofMillis(300))
                        // 4. Vets list
                        .exec(http("Vets").get("/vets.html"))
                        .pause(Duration.ofMillis(300))
                        // 5. Find owner form
                        .exec(http("Find owner form").get("/owners/find"))
                        .pause(Duration.ofMillis(300))
                        // 6. List all owners — HOTSPOT: findPaginatedForOwnersLastName
                        .exec(http("List all owners").get("/owners?lastName="))
                        .pause(Duration.ofMillis(300))
                        // 7. Owner detail
                        .exec(http("Owner detail").get("/owners/#{count}"))
                        .pause(Duration.ofMillis(300))
                        // 8. Edit owner form
                        .exec(http("Edit owner form").get("/owners/#{count}/edit"))
                        .pause(Duration.ofMillis(300))
                        // 9. POST edit owner
                        .exec(http("POST edit owner")
                                        .post("/owners/#{count}/edit")
                                        .formParam("firstName", "Test")
                                        .formParam("lastName", "#{count}")
                                        .formParam("address", "1234 Test St.")
                                        .formParam("city", "TestCity")
                                        .formParam("telephone", "612345678"))
                        .pause(Duration.ofMillis(300))
                        // 10. New pet form
                        .exec(http("New pet form").get("/owners/#{count}/pets/new"))
                        .pause(Duration.ofMillis(300))
                        // 11. POST new pet
                        .exec(http("POST new pet")
                                        .post("/owners/#{count}/pets/new")
                                        .formParam("name", "Test Fluffy #{petCount}")
                                        .formParam("birthDate", "2024-05-24")
                                        .formParam("type", "cat"))
                        .pause(Duration.ofMillis(300))
                        // 12. New visit form
                        .exec(http("New visit form").get("/owners/#{count}/pets/#{petCount}/visits/new"))
                        .pause(Duration.ofMillis(300))
                        // 13. POST new visit
                        .exec(http("POST new visit")
                                        .post("/owners/#{count}/pets/#{petCount}/visits/new")
                                        .formParam("date", "2026-05-24")
                                        .formParam("description", "visit"));

        {
                setUp(
                                scn.injectClosed(
                                                rampConcurrentUsers(1).to(USERS)
                                                                .during(Duration.ofSeconds(RAMP_SECONDS)),
                                                constantConcurrentUsers(USERS)
                                                                .during(Duration.ofSeconds(DURATION_SECONDS))))
                                .protocols(httpProtocol);
        }
}
