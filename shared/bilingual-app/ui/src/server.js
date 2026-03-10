const express = require('express');
const path = require('path');
const axios = require('axios');
const cookieParser = require('cookie-parser');
const pino = require('pino');
const pinoHttp = require('pino-http');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 8080;

// Structured JSON logger for load test analysis
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  base: {
    service: 'lab-shop-ui',
    version: '1.0.0',
    env: process.env.NODE_ENV || 'production',
  },
});

// HTTP request logging with response time
app.use(pinoHttp({
  logger,
  genReqId: (req) => req.headers['x-request-id'] || uuidv4(),
  customLogLevel: (req, res, err) => {
    if (res.statusCode >= 500 || err) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  },
  customSuccessMessage: (req, res) => {
    return `${req.method} ${req.url} ${res.statusCode}`;
  },
  serializers: {
    req: (req) => ({
      method: req.method,
      url: req.url,
      lang: req.lang,
      requestId: req.id,
      userAgent: req.headers['user-agent'],
      remoteAddress: req.remoteAddress,
    }),
    res: (res) => ({
      statusCode: res.statusCode,
    }),
  },
}));

app.use(cookieParser());
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// i18n translations
const locales = {
  ko: require('./locales/ko.json'),
  en: require('./locales/en.json'),
};

// Language detection middleware
app.use((req, res, next) => {
  let lang = req.query.lang || req.cookies.lang;
  if (!lang) {
    const acceptLang = req.headers['accept-language'] || '';
    lang = acceptLang.startsWith('ko') ? 'ko' : 'en';
  }
  if (!['ko', 'en'].includes(lang)) lang = 'en';
  req.lang = lang;
  res.cookie('lang', lang, { maxAge: 365 * 24 * 60 * 60 * 1000, httpOnly: false });
  res.locals.t = locales[lang];
  res.locals.lang = lang;
  res.locals.requestId = req.id;
  next();
});

// Backend service endpoints
const CATALOG_URL = process.env.ENDPOINTS_CATALOG || 'http://catalog.catalog:80';
const CARTS_URL = process.env.ENDPOINTS_CARTS || 'http://carts.carts:80';
const CHECKOUT_URL = process.env.ENDPOINTS_CHECKOUT || 'http://checkout.checkout:80';
const ORDERS_URL = process.env.ENDPOINTS_ORDERS || 'http://orders.orders:80';

// Helper: call backend with request ID propagation + timing
async function callBackend(url, reqId, method = 'get', data = null) {
  const start = Date.now();
  try {
    const config = {
      method,
      url,
      headers: { 'X-Request-ID': reqId, 'Content-Type': 'application/json', 'Accept': 'application/json' },
      timeout: 10000,
    };
    if (data) config.data = data;
    const res = await axios(config);
    const duration = Date.now() - start;
    logger.info({ backend: url, method, duration, status: res.status, requestId: reqId }, 'backend_call');
    return res.data;
  } catch (err) {
    const duration = Date.now() - start;
    logger.error({ backend: url, method, duration, error: err.message, requestId: reqId }, 'backend_error');
    return null;
  }
}

// Routes
app.get('/', async (req, res) => {
  let products = [];
  try {
    const data = await callBackend(`${CATALOG_URL}/catalogue`, req.id);
    if (data) products = Array.isArray(data) ? data.slice(0, 8) : [];
  } catch (e) { /* use empty */ }
  res.render('home', { products });
});

app.get('/catalog', async (req, res) => {
  let products = [];
  try {
    const data = await callBackend(`${CATALOG_URL}/catalogue`, req.id);
    if (data) products = Array.isArray(data) ? data : [];
  } catch (e) { /* use empty */ }
  res.render('catalog', { products });
});

app.get('/product/:id', async (req, res) => {
  let product = null;
  try {
    product = await callBackend(`${CATALOG_URL}/catalogue/product/${req.params.id}`, req.id);
  } catch (e) { /* null */ }
  if (!product) return res.status(404).render('error', { message: '404' });
  res.render('product', { product });
});

// Cart: add item
app.post('/cart/add', async (req, res) => {
  const { productId, productName, price, quantity } = req.body;
  const qty = parseInt(quantity) || 1;
  const item = {
    itemId: productId || 'unknown',
    unitPrice: parseFloat(price) || 0,
    quantity: qty,
  };
  await callBackend(`${CARTS_URL}/carts/1/items`, req.id, 'post', item);
  logger.info({ action: 'add_to_cart', productId, quantity: qty, requestId: req.id }, 'cart_action');
  res.redirect('/cart');
});

// Cart: update quantity
app.post('/cart/update', async (req, res) => {
  const { itemId, quantity } = req.body;
  const qty = parseInt(quantity) || 1;
  await callBackend(`${CARTS_URL}/carts/1/items/${itemId}`, req.id, 'put', { quantity: qty, unitPrice: 0 });
  res.redirect('/cart');
});

// Cart: remove item
app.post('/cart/remove', async (req, res) => {
  const { itemId } = req.body;
  await callBackend(`${CARTS_URL}/carts/1/items/${itemId}`, req.id, 'delete');
  logger.info({ action: 'remove_from_cart', itemId, requestId: req.id }, 'cart_action');
  res.redirect('/cart');
});

// Cart: view
app.get('/cart', async (req, res) => {
  let items = [];
  try {
    const data = await callBackend(`${CARTS_URL}/carts/1/items`, req.id);
    if (data) items = Array.isArray(data) ? data : [];
  } catch (e) { /* empty */ }
  res.render('cart', { items });
});

// Checkout: place order (2-step: update → submit)
app.post('/checkout/place-order', async (req, res) => {
  const { first_name: firstName, last_name: lastName, email, phone,
          province, city, town, street, building, detail, zip } = req.body;

  // Build full address string
  const fullAddress = [province, city, town, street, building, detail].filter(Boolean).join(' ');

  // Calculate subtotal from cart
  let subtotal = 0;
  let cartItems = [];
  try {
    cartItems = await callBackend(`${CARTS_URL}/carts/1/items`, req.id) || [];
    if (Array.isArray(cartItems)) {
      subtotal = cartItems.reduce((sum, item) => sum + (item.unitPrice || 0) * (item.quantity || 1), 0);
    }
  } catch (e) { /* default 0 */ }

  // Step 1: Update checkout session with shipping info
  const updateData = {
    customerEmail: email || 'guest@lab.shop',
    subtotal: Math.round(subtotal) || 100,
    shippingAddress: {
      firstName: firstName || 'Guest',
      lastName: lastName || 'User',
      address1: fullAddress || '서울특별시 강남구 테헤란로 152',
      city: city || province || 'Seoul',
      state: province || 'Seoul',
      zip: zip || '06236',
    },
  };

  logger.info({
    action: 'checkout_address',
    address: { province, city, town, street, building, detail, zip },
    phone,
    requestId: req.id,
  }, 'address_detail');
  const checkoutSession = await callBackend(`${CHECKOUT_URL}/checkout/1/update`, req.id, 'post', updateData);
  logger.info({ action: 'checkout_update', email, subtotal, requestId: req.id }, 'order_action');

  // Step 2: Create order directly via orders service (bypass checkout submit)
  // Re-fetch cart items (cartItems already declared above)
  try {
    cartItems = await callBackend(`${CARTS_URL}/carts/1/items`, req.id) || [];
  } catch (e) { /* empty */ }

  const orderPayload = {
    firstName: firstName || 'Guest',
    lastName: lastName || 'User',
    email: email || 'guest@lab.shop',
    items: cartItems.map(item => ({
      productId: item.itemId,
      name: item.itemId,
      quantity: item.quantity || 1,
      unitCost: item.unitPrice || 0,
      totalCost: (item.unitPrice || 0) * (item.quantity || 1),
    })),
  };
  const result = await callBackend(`${ORDERS_URL}/orders`, req.id, 'post', orderPayload);
  logger.info({ action: 'place_order', email, total: checkoutSession?.total, items: cartItems.length, requestId: req.id }, 'order_action');

  // Clear cart after order (delete items one by one)
  for (const item of cartItems) {
    await callBackend(`${CARTS_URL}/carts/1/items/${item.itemId}`, req.id, 'delete');
  }

  const orderId = result?.id || checkoutSession?.paymentId || 'pending';
  const total = checkoutSession?.total || subtotal;
  res.render('order-confirm', { order: { id: orderId, total } });
});

app.get('/orders', async (req, res) => {
  let orders = [];
  try {
    const data = await callBackend(`${ORDERS_URL}/orders`, req.id);
    if (data) orders = Array.isArray(data) ? data : [];
  } catch (e) { /* empty */ }
  res.render('orders', { orders });
});

app.get('/checkout', async (req, res) => {
  let items = [];
  try {
    const data = await callBackend(`${CARTS_URL}/carts/1/items`, req.id);
    if (data) items = Array.isArray(data) ? data : [];
  } catch (e) { /* empty */ }
  res.render('checkout', { items });
});

// Health check (structured log)
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'lab-shop-ui', timestamp: new Date().toISOString() });
});

// 404
app.use((req, res) => {
  res.status(404).render('error', { message: '404 Not Found' });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error({ err, requestId: req.id }, 'unhandled_error');
  res.status(500).render('error', { message: 'Internal Server Error' });
});

app.listen(PORT, '0.0.0.0', () => {
  logger.info({ port: PORT, catalogUrl: CATALOG_URL, cartsUrl: CARTS_URL }, 'server_started');
});
