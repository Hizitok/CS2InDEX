import { MarketMaker } from './bot';

async function main() {
    const bot = new MarketMaker();
    await bot.run();

    // Keep process alive
    process.on('SIGINT',  () => { console.log('\nShutting down…'); process.exit(0); });
    process.on('SIGTERM', () => { console.log('\nShutting down…'); process.exit(0); });
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
