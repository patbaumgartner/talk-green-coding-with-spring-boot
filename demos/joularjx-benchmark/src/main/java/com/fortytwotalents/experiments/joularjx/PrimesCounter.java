package com.fortytwotalents.experiments.joularjx;

import java.util.stream.IntStream;

public class PrimesCounter {

	public static void main(String[] args) {
		var lowerBound = 2;
		var upperBound = 100_000_000;

		var startTime = System.nanoTime();
		var count = countPrimesInRange(lowerBound, upperBound);
		var endTime = System.nanoTime();

		var durationInMillis = (endTime - startTime) / 1_000_000;

		System.out.printf("Number of primes between %d and %d: %d%n", lowerBound, upperBound, count);
		System.out.printf("Time taken: %d ms%n", durationInMillis);
	}

	private static long countPrimesInRange(int lowerBound, int upperBound) {
		return IntStream.range(lowerBound, upperBound).filter(number -> isPrime(number)).count();
	}

	private static boolean isPrime(int n) {
		if (n < 2) {
			return false;
		}
		if (n == 2) {
			return true;
		}
		if (n % 2 == 0) {
			return false;
		}
		for (int factor = 3; factor * factor <= n; factor += 2) {
			if (n % factor == 0) {
				return false;
			}
		}
		return true;
	}

}
