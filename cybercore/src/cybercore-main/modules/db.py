import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
import bcrypt
from datetime import datetime
from contextlib import contextmanager
from typing import Optional, List, Dict, Any
import logging

logger = logging.getLogger(__name__)


class DatabaseManager:
    def __init__(self, config: dict):
        self.config = config
        self._pool = None
        self._initialize_pool()
    
    def _initialize_pool(self):
        """Initialize connection pool"""
        try:
            self._pool = psycopg2.pool.SimpleConnectionPool(
                1, 20,  # min and max connections
                host=self.config['host'],
                port=self.config['port'],
                database=self.config['database'],
                user=self.config['user'],
                password=self.config['password']
            )
            logger.info("Database connection pool initialized")
        except Exception as e:
            logger.error(f"Failed to initialize database pool: {e}")
            raise
    
    @contextmanager
    def get_connection(self):
        """Get a connection from the pool"""
        conn = None
        try:
            conn = self._pool.getconn()
            yield conn
            conn.commit()
        except Exception as e:
            if conn:
                conn.rollback()
            raise e
        finally:
            if conn:
                self._pool.putconn(conn)
    
    @contextmanager
    def get_cursor(self, cursor_factory=RealDictCursor):
        """Get a cursor with automatic connection management"""
        with self.get_connection() as conn:
            cursor = conn.cursor(cursor_factory=cursor_factory)
            try:
                yield cursor
            finally:
                cursor.close()
    
    def close(self):
        """Close all connections in the pool"""
        if self._pool:
            self._pool.closeall()


class UserManager:
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
    
    def _hash_password(self, password: str) -> bytes:
        """Hash a password using bcrypt"""
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    
    def _verify_password(self, password: str, hashed: bytes) -> bool:
        """Verify a password against a hash"""
        return bcrypt.checkpw(password.encode('utf-8'), hashed)
    
    def create_user(self, username: str, email: Optional[str] = None, 
                   password: Optional[str] = None, first_name: Optional[str] = None,
                   last_name: Optional[str] = None) -> Dict[str, Any]:
        """Create a new user"""
        with self.db.get_cursor() as cursor:
            # Check if user already exists
            cursor.execute("SELECT id FROM users WHERE username = %s", (username,))
            if cursor.fetchone():
                raise ValueError(f"User '{username}' already exists")
            
            # Prepare user data
            password_hash = self._hash_password(password) if password else None
            full_name = f"{first_name} {last_name}".strip() if first_name or last_name else None
            
            # Insert user
            cursor.execute("""
                INSERT INTO users (username, email, first_name, last_name, full_name, 
                                 password_hash, password_algo)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING *
            """, (username, email, first_name, last_name, full_name, 
                  password_hash, 'bcrypt' if password_hash else None))
            
            user = cursor.fetchone()
            logger.info(f"Created user: {username}")
            return dict(user)
    
    def list_users(self, active_only: bool = True) -> List[Dict[str, Any]]:
        """List all users"""
        with self.db.get_cursor() as cursor:
            query = "SELECT * FROM users"
            if active_only:
                query += " WHERE active = true AND deleted_at IS NULL"
            query += " ORDER BY username"
            
            cursor.execute(query)
            return [dict(row) for row in cursor.fetchall()]
    
    def get_user(self, username: str) -> Optional[Dict[str, Any]]:
        """Get a single user by username"""
        with self.db.get_cursor() as cursor:
            cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
            user = cursor.fetchone()
            return dict(user) if user else None
    
    def update_user(self, username: str, **kwargs) -> Optional[Dict[str, Any]]:
        """Update user information"""
        allowed_fields = ['email', 'first_name', 'last_name', 'active', 'status']
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        
        if not updates:
            return None
        
        # Handle password separately
        if 'password' in kwargs:
            updates['password_hash'] = self._hash_password(kwargs['password'])
            updates['password_algo'] = 'bcrypt'
        
        # Update full_name if names changed
        if 'first_name' in updates or 'last_name' in updates:
            with self.db.get_cursor() as cursor:
                cursor.execute("SELECT first_name, last_name FROM users WHERE username = %s", 
                             (username,))
                current = cursor.fetchone()
                if current:
                    fname = updates.get('first_name', current['first_name'])
                    lname = updates.get('last_name', current['last_name'])
                    updates['full_name'] = f"{fname} {lname}".strip() if fname or lname else None
        
        # Build update query
        set_clause = ", ".join([f"{k} = %s" for k in updates.keys()])
        values = list(updates.values()) + [username]
        
        with self.db.get_cursor() as cursor:
            cursor.execute(f"""
                UPDATE users 
                SET {set_clause}, updated_at = NOW()
                WHERE username = %s
                RETURNING *
            """, values)
            
            user = cursor.fetchone()
            if user:
                logger.info(f"Updated user: {username}")
                return dict(user)
            return None
    
    def delete_user(self, username: str, soft_delete: bool = True) -> bool:
        """Delete a user (soft delete by default)"""
        with self.db.get_cursor() as cursor:
            if soft_delete:
                cursor.execute("""
                    UPDATE users 
                    SET deleted_at = NOW(), active = false, status = 'deleted'
                    WHERE username = %s AND deleted_at IS NULL
                    RETURNING id
                """, (username,))
            else:
                cursor.execute("DELETE FROM users WHERE username = %s RETURNING id", 
                             (username,))
            
            result = cursor.fetchone()
            if result:
                logger.info(f"{'Soft' if soft_delete else 'Hard'} deleted user: {username}")
                return True
            return False
    
    def authenticate(self, username: str, password: str) -> Optional[Dict[str, Any]]:
        """Authenticate a user with password"""
        user = self.get_user(username)
        if not user or not user.get('password_hash'):
            return None
        
        if user['active'] and self._verify_password(password, bytes(user['password_hash'])):
            return user
        return None