String googleFinanceUrl(String yahooSymbol, {String? yahooExchange}) {
  final symbol = yahooSymbol.trim().toUpperCase();
  final colon = symbol.lastIndexOf(':');
  if (colon > 0 && colon < symbol.length - 1) {
    return 'https://www.google.com/finance/quote/'
        '${Uri.encodeComponent(symbol.substring(0, colon))}:'
        '${Uri.encodeComponent(symbol.substring(colon + 1))}';
  }

  final suffix = symbol.lastIndexOf('.');
  final market = suffix < 0 ? null : _suffixMarkets[symbol.substring(suffix)];
  final exchange = market ?? _yahooMarkets[yahooExchange?.trim().toUpperCase()];
  if (exchange == null || exchange.isEmpty) {
    return 'https://www.google.com/finance/search?q=${Uri.encodeQueryComponent(symbol)}';
  }
  final ticker = market == null ? symbol : symbol.substring(0, suffix);
  return 'https://www.google.com/finance/quote/'
      '${Uri.encodeComponent(ticker)}:$exchange';
}

const _suffixMarkets = <String, String>{
  '.AX': 'ASX',
  '.NZ': 'NZE',
  '.L': 'LON',
  '.TO': 'TSE',
  '.V': 'CVE',
  '.PA': 'EPA',
  '.DE': 'ETR',
  '.F': 'FRA',
  '.HK': 'HKG',
  '.SW': 'SWX',
  '.SI': 'SGX',
  '.SA': 'BVMF',
  '.NS': 'NSE',
  '.BO': 'BOM',
  '.T': 'TYO',
  '.KS': 'KRX',
  '.KQ': 'KOSDAQ',
};

const _yahooMarkets = <String, String>{
  'NMS': 'NASDAQ',
  'NGM': 'NASDAQ',
  'NCM': 'NASDAQ',
  'NASDAQ': 'NASDAQ',
  'NYQ': 'NYSE',
  'NYS': 'NYSE',
  'NYSE': 'NYSE',
  'ASE': 'NYSEAMERICAN',
  'AMEX': 'NYSEAMERICAN',
  'PCX': 'NYSEARCA',
  'ARCA': 'NYSEARCA',
  'BTS': 'BATS',
  'LSE': 'LON',
  'ASX': 'ASX',
  'NZE': 'NZE',
  'NZX': 'NZE',
  'TOR': 'TSE',
  'VAN': 'CVE',
  'GER': 'ETR',
  'FRA': 'FRA',
  'PAR': 'EPA',
  'HKG': 'HKG',
  'SWX': 'SWX',
  'SES': 'SGX',
  'SAO': 'BVMF',
  'NSI': 'NSE',
  'BSE': 'BOM',
  'JPX': 'TYO',
  'KSC': 'KRX',
  'KOE': 'KOSDAQ',
};
