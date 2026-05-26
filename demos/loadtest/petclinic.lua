-- petclinic.lua — wrk / wrk2 load script for spring-petclinic
--
-- URL mix mirrors the JMeter test plan (petclinic_test_plan.jmx).
--
-- Usage:
--   wrk2 -t2 -c10 -d60s -R100 --latency -s petclinic.lua http://localhost:8080
--   wrk  -t2 -c10 -d60s          --latency -s petclinic.lua http://localhost:8080

local counter = 0

local paths = {
    "/",                     -- Home page
    "/vets.html",            -- VetController.findPaginated
    "/owners/find",          -- Owner search form
    "/owners?lastName=",     -- HOTSPOT: findPaginatedForOwnersLastName
    "/owners?lastName=",     -- weighted 2x — makes hotspot clearly visible in profile
    "/owners/1",             -- OwnerController.findOwner
    "/owners/2",
    "/owners/3",
    "/owners/4",
    "/owners/5",
}

request = function()
    counter = counter + 1
    local path = paths[(counter % #paths) + 1]
    return wrk.format("GET", path)
end
