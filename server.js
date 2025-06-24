const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const winston = require('winston');
const path = require('path');
const fs = require('fs');
require('dotenv').config();

const config = loadConfiguration();
const logger = setupLogging();

class PostgreSQLFYIService {
  constructor() {
    this.app = express();
    this.server = null;
    this.connections = new Map();
    this.config = config;

    this.setupMiddleware();
    this.setupRoutes();
    this.setupGracefulShutdown();
  }

  setupMiddleware() {
    // CORS configuration
    this.app.use(cors({
      origin: (origin, callback) => {
        // Allow requests with no origin (like mobile apps or curl requests)
        if (!origin) return callback(null, true);

        // Allow localhost and development origins
        if (origin.includes('localhost') || origin.includes('127.0.0.1') || origin.includes('file://')) {
          return callback(null, true);
        }

        // Allow configured origins
        if (this.config.corsOrigins.includes(origin) || this.config.corsOrigins.includes('*')) {
          return callback(null, true);
        }

        callback(new Error('Not allowed by CORS'));
      },
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'HEAD'],
      allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-Connection-ID',
        'X-Requested-With',
        'Accept',
        'Origin'
      ],
      preflightContinue: false,
      optionsSuccessStatus: 200
    }));

    // Handle preflight requests
    this.app.options('*', (req, res) => {
      res.header('Access-Control-Allow-Origin', req.headers.origin || '*');
      res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, HEAD');
      res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Connection-ID, X-Requested-With, Accept, Origin');
      res.header('Access-Control-Allow-Credentials', 'true');
      res.sendStatus(200);
    });

    // Body parsing
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true }));

    // Request logging
    this.app.use((req, res, next) => {
      logger.info(`${req.method} ${req.path}`, {
        ip: req.ip,
        userAgent: req.get('User-Agent'),
        origin: req.headers.origin
      });
      next();
    });

    // Error handling
    this.app.use((err, req, res, next) => {
      logger.error('Server error:', err);
      res.status(500).json({
        success: false,
        error: 'Internal server error',
        details: process.env.NODE_ENV === 'development' ? err.message : undefined
      });
    });
  }

  setupRoutes() {
    // Health check
    this.app.get('/health', (req, res) => {
      res.json({
        success: true,
        status: 'healthy',
        timestamp: new Date().toISOString(),
        activeConnections: this.connections.size,
        uptime: process.uptime(),
        version: require('./package.json').version
      });
    });

    // Service info
    this.app.get('/info', (req, res) => {
      res.json({
        success: true,
        service: 'PostgreSQL FYI',
        version: require('./package.json').version,
        nodeVersion: process.version,
        config: {
          port: this.config.port,
          maxConnections: this.config.maxConnections,
          corsOrigins: this.config.corsOrigins,
          environment: process.env.NODE_ENV || 'production'
        }
      });
    });

    // Connect to database
    this.app.post('/connect', async (req, res) => {
      try {
        const { host, port, database, username, password, sslMode } = req.body;

        if (!host || !database || !username || !password) {
          return res.status(400).json({
            success: false,
            error: 'Missing required connection parameters: host, database, username, password'
          });
        }

        const connectionId = this.generateConnectionId();

        // Determine SSL configuration
        let sslConfig = this.determineSSLConfig(host, sslMode);

        const pool = new Pool({
          host,
          port: port || 5432,
          database,
          user: username,
          password,
          max: 5,
          idleTimeoutMillis: 30000,
          connectionTimeoutMillis: this.config.connectionTimeout,
          ssl: sslConfig
        });

        // Test the connection
        const client = await pool.connect();
        const result = await client.query('SELECT version(), current_database(), current_user');
        client.release();

        // Store the connection
        this.connections.set(connectionId, {
          pool,
          config: { host, port, database, username },
          createdAt: new Date(),
          lastUsed: new Date()
        });

        logger.info(`New database connection established`, {
          connectionId,
          host,
          database,
          username
        });

        res.json({
          success: true,
          connectionId,
          database: result.rows[0],
          message: 'Connected successfully'
        });

      } catch (error) {
        logger.error('Database connection failed:', {
          error: error.message,
          host: req.body.host,
          database: req.body.database
        });

        res.status(500).json({
          success: false,
          error: 'Connection failed',
          details: error.message
        });
      }
    });

    // Execute query
    this.app.post('/query', async (req, res) => {
      try {
        const { connectionId, sql } = req.body;

        if (!connectionId || !sql) {
          return res.status(400).json({
            success: false,
            error: 'Missing connectionId or sql'
          });
        }

        const connection = this.connections.get(connectionId);
        if (!connection) {
          return res.status(404).json({
            success: false,
            error: 'Connection not found'
          });
        }

        // No SQL restrictions - allow any command
        const startTime = Date.now();
        const result = await connection.pool.query(sql);
        const duration = Date.now() - startTime;

        // Update last used time
        connection.lastUsed = new Date();

        logger.info('Query executed successfully:', {
          connectionId,
          duration,
          rowCount: result.rowCount,
          sql: sql.substring(0, 100) + (sql.length > 100 ? '...' : '')
        });

        res.json({
          success: true,
          data: {
            rows: result.rows,
            rowCount: result.rowCount,
            fields: result.fields?.map(field => ({
              name: field.name,
              dataTypeID: field.dataTypeID,
              dataTypeSize: field.dataTypeSize
            })),
            duration
          }
        });

      } catch (error) {
        logger.error('Query execution failed:', {
          error: error.message,
          connectionId: req.body.connectionId,
          sql: req.body.sql
        });

        res.status(500).json({
          success: false,
          error: 'Query execution failed',
          details: error.message
        });
      }
    });

    // Get database schema
    this.app.get('/schema/:connectionId', async (req, res) => {
      try {
        const { connectionId } = req.params;

        const connection = this.connections.get(connectionId);
        if (!connection) {
          return res.status(404).json({
            success: false,
            error: 'Connection not found'
          });
        }

        const schemaQuery = `
          SELECT 
            t.table_name,
            t.table_type,
            c.column_name,
            c.data_type,
            c.is_nullable,
            c.column_default,
            c.ordinal_position
          FROM information_schema.tables t
          LEFT JOIN information_schema.columns c ON t.table_name = c.table_name
          WHERE t.table_schema = 'public'
          ORDER BY t.table_name, c.ordinal_position
        `;

        const result = await connection.pool.query(schemaQuery);

        // Group by table
        const schema = {};
        result.rows.forEach(row => {
          if (!schema[row.table_name]) {
            schema[row.table_name] = {
              type: row.table_type,
              columns: []
            };
          }

          if (row.column_name) {
            schema[row.table_name].columns.push({
              name: row.column_name,
              type: row.data_type,
              nullable: row.is_nullable === 'YES',
              default: row.column_default,
              position: row.ordinal_position
            });
          }
        });

        res.json({
          success: true,
          schema
        });

      } catch (error) {
        logger.error('Schema fetch failed:', {
          error: error.message,
          connectionId: req.params.connectionId
        });

        res.status(500).json({
          success: false,
          error: 'Failed to fetch schema',
          details: error.message
        });
      }
    });

    // Disconnect
    this.app.post('/disconnect', async (req, res) => {
      try {
        const { connectionId } = req.body;

        const connection = this.connections.get(connectionId);
        if (!connection) {
          return res.status(404).json({
            success: false,
            error: 'Connection not found'
          });
        }

        await connection.pool.end();
        this.connections.delete(connectionId);

        logger.info('Database connection closed:', { connectionId });

        res.json({
          success: true,
          message: 'Disconnected successfully'
        });

      } catch (error) {
        logger.error('Disconnect failed:', {
          error: error.message,
          connectionId: req.body.connectionId
        });

        res.status(500).json({
          success: false,
          error: 'Disconnect failed',
          details: error.message
        });
      }
    });

    // List active connections
    this.app.get('/connections', (req, res) => {
      const connections = Array.from(this.connections.entries()).map(([id, conn]) => ({
        id,
        database: conn.config.database,
        host: conn.config.host,
        port: conn.config.port,
        username: conn.config.username,
        createdAt: conn.createdAt,
        lastUsed: conn.lastUsed
      }));

      res.json({
        success: true,
        connections
      });
    });
  }

  determineSSLConfig(host, sslMode) {
    if (sslMode === 'auto') {
      const isLocalhost = host === 'localhost' || host === '127.0.0.1' ||
        host.startsWith('192.168') || host.startsWith('10.');
      return isLocalhost ? false : {
        rejectUnauthorized: false,
        sslmode: 'require'
      };
    } else if (sslMode === 'require') {
      return {
        rejectUnauthorized: false,
        sslmode: 'require'
      };
    } else if (sslMode === 'prefer') {
      return {
        rejectUnauthorized: false,
        sslmode: 'prefer'
      };
    } else if (sslMode === 'disable') {
      return false;
    }

    return false; // default
  }

  generateConnectionId() {
    return 'conn_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  setupGracefulShutdown() {
    const shutdown = async (signal) => {
      logger.info(`Received ${signal}, shutting down gracefully...`);

      // Close all database connections
      for (const [id, connection] of this.connections) {
        try {
          await connection.pool.end();
          logger.info(`Closed database connection: ${id}`);
        } catch (error) {
          logger.error(`Error closing connection ${id}:`, error);
        }
      }
      this.connections.clear();

      // Close HTTP server
      if (this.server) {
        this.server.close(() => {
          logger.info('HTTP server closed');
          process.exit(0);
        });
      } else {
        process.exit(0);
      }
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  }

  async start() {
    return new Promise((resolve, reject) => {
      this.server = this.app.listen(this.config.port, this.config.host, (error) => {
        if (error) {
          logger.error('Failed to start server:', error);
          reject(error);
        } else {
          logger.info(`🐘 PostgreSQL FYI Service started`, {
            port: this.config.port,
            host: this.config.host,
            environment: process.env.NODE_ENV || 'production',
            corsOrigins: this.config.corsOrigins
          });

          // Start cleanup interval
          this.startCleanupInterval();
          resolve();
        }
      });
    });
  }

  startCleanupInterval() {
    setInterval(() => {
      const now = new Date();
      const maxAge = this.config.connectionMaxAge;

      for (const [id, connection] of this.connections) {
        if (now - connection.lastUsed > maxAge) {
          logger.info(`Cleaning up old connection: ${id}`);
          connection.pool.end().catch(error =>
            logger.error(`Error cleaning up connection ${id}:`, error)
          );
          this.connections.delete(id);
        }
      }
    }, this.config.cleanupInterval);
  }
}

// Configuration loader
function loadConfiguration() {
  // Load file config first
  let fileConfig = {};
  const configPath = path.join(__dirname, 'config', 'default.json');
  if (fs.existsSync(configPath)) {
    try {
      fileConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } catch (error) {
      console.warn('Warning: Could not load config file, using defaults');
    }
  }

  // Default config (lowest priority)
  const defaultConfig = {
    port: 1234,
    host: 'localhost',
    corsOrigins: ['*'],
    maxConnections: 5,
    connectionTimeout: 30000,
    connectionMaxAge: 120 * 60 * 1000, // 120 minutes
    cleanupInterval: 5 * 60 * 1000, // 5 minutes
    logLevel: 'info',
    logFile: process.env.NODE_ENV === 'development' ?
      './logs/service.log' : '/var/log/postgresql-fyi/service.log'
  };

  // Environment variables (highest priority)
  const envConfig = {
    ...(process.env.PORT && { port: parseInt(process.env.PORT) }),
    ...(process.env.HOST && { host: process.env.HOST }),
    ...(process.env.CORS_ORIGINS && { corsOrigins: process.env.CORS_ORIGINS.split(',') }),
    ...(process.env.MAX_CONNECTIONS && { maxConnections: parseInt(process.env.MAX_CONNECTIONS) }),
    ...(process.env.CONNECTION_TIMEOUT && { connectionTimeout: parseInt(process.env.CONNECTION_TIMEOUT) }),
    ...(process.env.CONNECTION_MAX_AGE && { connectionMaxAge: parseInt(process.env.CONNECTION_MAX_AGE) }),
    ...(process.env.CLEANUP_INTERVAL && { cleanupInterval: parseInt(process.env.CLEANUP_INTERVAL) }),
    ...(process.env.LOG_LEVEL && { logLevel: process.env.LOG_LEVEL }),
    ...(process.env.LOG_FILE && { logFile: process.env.LOG_FILE })
  };

  // Merge in priority order: defaults < file < environment
  return { ...defaultConfig, ...fileConfig, ...envConfig };
}

function setupLogging() {
  const logFile = process.env.LOG_FILE || (process.env.NODE_ENV === 'development' ?
    './logs/service.log' : '/var/log/postgresql-fyi/service.log');

  const logDir = path.dirname(logFile);

  try {
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
  } catch (error) {
    // In development, fallback to console-only logging if we can't create log dir
    if (process.env.NODE_ENV === 'development') {
      console.warn(`Warning: Could not create log directory ${logDir}, using console-only logging`);
      return winston.createLogger({
        level: config.logLevel,
        format: winston.format.combine(
          winston.format.timestamp(),
          winston.format.errors({ stack: true }),
          winston.format.colorize(),
          winston.format.simple()
        ),
        defaultMeta: { service: 'postgresql-fyi' },
        transports: [
          new winston.transports.Console()
        ]
      });
    }
    throw error;
  }

  return winston.createLogger({
    level: config.logLevel,
    format: winston.format.combine(
      winston.format.timestamp(),
      winston.format.errors({ stack: true }),
      winston.format.json()
    ),
    defaultMeta: { service: 'postgresql-fyi' },
    transports: [
      new winston.transports.File({
        filename: logFile,
        maxsize: 5 * 1024 * 1024, // 5MB
        maxFiles: 2
      }),
      new winston.transports.Console({
        format: winston.format.combine(
          winston.format.colorize(),
          winston.format.simple()
        )
      })
    ]
  });
}

if (require.main === module) {
  const service = new PostgreSQLFYIService();

  service.start().catch((error) => {
    console.error('Failed to start PostgreSQL FYI Service:', error);
    process.exit(1);
  });
}

module.exports = PostgreSQLFYIService;