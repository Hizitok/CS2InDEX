/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  optimizeFonts: false,
  webpack: (config) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    config.externals.push('pino-pretty', 'lokijs', 'encoding');
    // Ignore React Native modules in Next.js
    config.resolve.alias = {
      ...config.resolve.alias,
      '@react-native-async-storage/async-storage': false,
    };
    return config;
  },
}

module.exports = nextConfig
