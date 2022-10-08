package org.argeo.build;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.PathMatcher;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.StringTokenizer;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;

import aQute.bnd.osgi.Analyzer;
import aQute.bnd.osgi.Jar;

public class Make {
	private final static String SDK_MK = "sdk.mk";

	final Path execDirectory;
	final Path sdkSrcBase;
	final Path argeoBuildBase;
	final Path sdkBuildBase;
	final Path buildBase;

	public Make() throws IOException {
		execDirectory = Paths.get(System.getProperty("user.dir"));
		Path sdkMkP = findSdkMk(execDirectory);
		Objects.requireNonNull(sdkMkP, "No " + SDK_MK + " found under " + execDirectory);

		Map<String, String> context = new HashMap<>();
		List<String> sdkMkLines = Files.readAllLines(sdkMkP);
		lines: for (String line : sdkMkLines) {
			StringTokenizer st = new StringTokenizer(line, " :=");
			if (!st.hasMoreTokens())
				continue lines;
			String key = st.nextToken();
			if (!st.hasMoreTokens())
				continue lines;
			String value = st.nextToken();
			context.put(key, value);
		}

		sdkSrcBase = Paths.get(context.computeIfAbsent("SDK_SRC_BASE", (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		argeoBuildBase = sdkSrcBase.resolve("sdk/argeo-build");

		sdkBuildBase = Paths.get(context.computeIfAbsent("SDK_BUILD_BASE", (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		buildBase = sdkBuildBase.resolve(sdkSrcBase.getFileName());
	}

	/*
	 * ACTIONS
	 */

	void bundle(Map<String, List<String>> options) throws IOException {
//		// generate manifests
//		subDirs: for (Path subDir : Files.newDirectoryStream(buildBase, (p) -> Files.isDirectory(p))) {
//			String bundleSymbolicName = subDir.getFileName().toString();
//			if (!bundleSymbolicName.contains("."))
//				continue subDirs;
//			generateManifest(bundleSymbolicName, subDir);
//		}

		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");

		// create jars
		subDirs: for (String bundle : bundles) {
			Path source = sdkSrcBase.resolve(bundle);
//			String bundleSymbolicName = source.getFileName().toString();
			Path compiled = buildBase.resolve(bundle);
//			if (!bundleSymbolicName.contains("."))
//				continue subDirs;
//			if (!Files.exists(source))
//				continue subDirs;
			Path jarP = buildBase.resolve(compiled.getFileName() + ".jar");
			createBundle(source, compiled, jarP);
		}

	}

	/*
	 * BND
	 */

//	void generateManifest(String bundleSymbolicName, Path compiled) throws IOException {
//		Properties properties = new Properties();
//		Path argeoBnd = argeoBuildBase.resolve("argeo.bnd");
//		try (InputStream in = Files.newInputStream(argeoBnd)) {
//			properties.load(in);
//		}
//		// FIXME make it configurable
//		Path branchBnd = sdkSrcBase.resolve("cnf/unstable.bnd");
//		try (InputStream in = Files.newInputStream(branchBnd)) {
//			properties.load(in);
//		}
//
//		Path bndBnd = compiled.resolve("bnd.bnd");
//		try (InputStream in = Files.newInputStream(bndBnd)) {
//			properties.load(in);
//		}
//
//		// Normalise
//		properties.put("Bundle-SymbolicName", bundleSymbolicName);
//
//		// Calculate MANIFEST
//		Path binP = compiled.resolve("bin");
//		Manifest manifest;
//		try (Analyzer bndAnalyzer = new Analyzer()) {
//			bndAnalyzer.setProperties(properties);
//			Jar jar = new Jar(bundleSymbolicName, binP.toFile());
//			bndAnalyzer.setJar(jar);
//			manifest = bndAnalyzer.calcManifest();
//
////			keys: for (Object key : manifest.getMainAttributes().keySet()) {
////				System.out.println(key + ": " + manifest.getMainAttributes().getValue(key.toString()));
////			}
//		} catch (Exception e) {
//			throw new RuntimeException("Bnd analysis of " + compiled + " failed", e);
//		}
//
//		// Write manifest
//		Path manifestP = compiled.resolve("META-INF/MANIFEST.MF");
//		Files.createDirectories(manifestP.getParent());
//		try (OutputStream out = Files.newOutputStream(manifestP)) {
//			manifest.write(out);
//		}
//	}

	/*
	 * JAR PACKAGING
	 */
	void createBundle(Path source, Path compiled, Path jarP) throws IOException {
		String bundleSymbolicName = source.getFileName().toString();

		// Metadata
		Properties properties = new Properties();
		Path argeoBnd = argeoBuildBase.resolve("argeo.bnd");
		try (InputStream in = Files.newInputStream(argeoBnd)) {
			properties.load(in);
		}
		// FIXME make it configurable
		Path branchBnd = sdkSrcBase.resolve("cnf/unstable.bnd");
		try (InputStream in = Files.newInputStream(branchBnd)) {
			properties.load(in);
		}

		Path bndBnd = source.resolve("bnd.bnd");
		try (InputStream in = Files.newInputStream(bndBnd)) {
			properties.load(in);
		}

		// Normalise
		properties.put("Bundle-SymbolicName", bundleSymbolicName);

		// Calculate MANIFEST
		Path binP = compiled.resolve("bin");
		Manifest manifest;
		try (Analyzer bndAnalyzer = new Analyzer()) {
			bndAnalyzer.setProperties(properties);
			Jar jar = new Jar(bundleSymbolicName, binP.toFile());
			bndAnalyzer.setJar(jar);
			manifest = bndAnalyzer.calcManifest();

//			keys: for (Object key : manifest.getMainAttributes().keySet()) {
//				System.out.println(key + ": " + manifest.getMainAttributes().getValue(key.toString()));
//			}
		} catch (Exception e) {
			throw new RuntimeException("Bnd analysis of " + compiled + " failed", e);
		}

		// Write manifest
//		Path manifestP = compiled.resolve("META-INF/MANIFEST.MF");
//		Files.createDirectories(manifestP.getParent());
//		try (OutputStream out = Files.newOutputStream(manifestP)) {
//			manifest.write(out);
//		}
//		
//		// Load manifest
//		Path manifestP = compiled.resolve("META-INF/MANIFEST.MF");
//		if (!Files.exists(manifestP))
//			throw new IllegalStateException("Manifest " + manifestP + " not found");
//		Manifest manifest;
//		try (InputStream in = Files.newInputStream(manifestP)) {
//			manifest = new Manifest(in);
//		} catch (IOException e) {
//			throw new IllegalStateException("Cannot read manifest " + manifestP, e);
//		}

		// Load excludes
		List<PathMatcher> excludes = new ArrayList<>();
		Path excludesP = argeoBuildBase.resolve("excludes.txt");
		for (String line : Files.readAllLines(excludesP)) {
			PathMatcher pathMatcher = excludesP.getFileSystem().getPathMatcher("glob:" + line);
			excludes.add(pathMatcher);
		}

		Files.createDirectories(jarP.getParent());
		try (JarOutputStream jarOut = new JarOutputStream(Files.newOutputStream(jarP), manifest)) {
			// add all classes first
//			Path binP = compiled.resolve("bin");
			Files.walkFileTree(binP, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					jarOut.putNextEntry(new JarEntry(binP.relativize(file).toString()));
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

			// add resources
			Files.walkFileTree(source, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
					Path relativeP = source.relativize(dir);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.SKIP_SUBTREE;

					return FileVisitResult.CONTINUE;
				}

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					Path relativeP = source.relativize(file);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.CONTINUE;
					JarEntry entry = new JarEntry(relativeP.toString());
					jarOut.putNextEntry(entry);
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}

			});

			// add sources
			// TODO add effective BND, Eclipse project file, etc., in order to be able to
			// repackage
			Path srcP = source.resolve("src");
			Files.walkFileTree(srcP, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					jarOut.putNextEntry(new JarEntry("OSGI-OPT/src/" + srcP.relativize(file).toString()));
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

		}

	}

	private Path findSdkMk(Path directory) {
		Path sdkMkP = directory.resolve(SDK_MK);
		if (Files.exists(sdkMkP)) {
			return sdkMkP.toAbsolutePath();
		}
		if (directory.getParent() == null)
			return null;
		return findSdkMk(directory.getParent());

	}

	public static void main(String... args) throws IOException {
		if (args.length == 0)
			throw new IllegalArgumentException("At least an action must be provided");
		int actionIndex = 0;
		String action = args[actionIndex];
		if (args.length > actionIndex + 1 && !args[actionIndex + 1].startsWith("-"))
			throw new IllegalArgumentException(
					"Action " + action + " must be followed by an option: " + Arrays.asList(args));

		Map<String, List<String>> options = new HashMap<>();
		String currentOption = null;
		for (int i = actionIndex + 1; i < args.length; i++) {
			if (args[i].startsWith("-")) {
				currentOption = args[i];
				if (!options.containsKey(currentOption))
					options.put(currentOption, new ArrayList<>());

			} else {
				options.get(currentOption).add(args[i]);
			}
		}
		
		Make argeoMake = new Make();
		switch (action) {
		case "bundle" -> argeoMake.bundle(options);
		default -> throw new IllegalArgumentException("Unkown action: " + action);
		}

	}
}
