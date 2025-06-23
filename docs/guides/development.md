# Development Guide

> **Target**: Developers contributing to the XR Future Forests Lab  
> **Prerequisites**: Docker, Python 3.9+, Git  
> **Time to setup**: 10 minutes

This guide covers everything needed to develop, test, and contribute to the XR Future Forests Lab.

## 🚀 **Quick Development Setup**

### 1. Environment Setup

```bash
# Clone and enter repository
git clone <repository-url>
cd xr-future-forests-lab

# Run setup script
./setup.sh

# Start development environment
docker-compose up -d

# Verify everything works
curl http://localhost:8000/health
```

### 2. Python Development Environment

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -e ".[dev]"

# Verify development tools
pytest --version
black --version
mypy --version
```

### 3. Verify Setup

```bash
# Run tests
pytest

# Check code formatting
black --check src/
isort --check-only src/

# Type checking
mypy src/

# API health check
curl http://localhost:8000/health
```

## 📁 **Project Structure Understanding**

### Source Code Organization

```text
src/xr_forests/
├── api/                    # Web API layer
│   ├── main.py            # FastAPI app factory
│   ├── exception_handlers.py
│   └── routers/           # Endpoint definitions
│       ├── health.py      # Health monitoring
│       ├── locations.py   # Forest locations
│       ├── trees.py       # Tree management
│       ├── point_cloud.py # 3D data processing
│       ├── environment.py # Environmental data
│       ├── species.py     # Species database
│       └── sensors.py     # Sensor management
├── core/                  # Business logic
│   ├── models/           # Database models
│   ├── schemas/          # API request/response schemas
│   └── services/         # Business logic services
└── database/             # Data access layer
    └── connection.py     # Database configuration
```

### Development Workflow

```text
API Router → Service Layer → Database Repository → PostgreSQL
     ↓             ↓              ↓
Schema Validation → Business Logic → Data Persistence
```

## 🔧 **Development Tasks**

### Adding a New API Endpoint

**Example**: Adding tree health assessment endpoints

1. **Define Database Model** (`src/xr_forests/core/models/tree.py`)

```python
class TreeHealthAssessment(Base, TimestampMixin):
    __tablename__ = "tree_health_assessments"
    
    id = Column(UUID, primary_key=True, default=uuid.uuid4)
    tree_id = Column(UUID, ForeignKey("trees.id"), nullable=False)
    assessment_date = Column(Date, nullable=False)
    health_status = Column(Enum(TreeStatus), nullable=False)
    notes = Column(Text)
```

2. **Create API Schemas** (`src/xr_forests/core/schemas/tree.py`)

```python
class TreeHealthAssessmentCreate(BaseModel):
    tree_id: UUID
    assessment_date: date
    health_status: TreeStatus
    notes: Optional[str] = None

class TreeHealthAssessmentResponse(BaseModel):
    id: UUID
    tree_id: UUID
    assessment_date: date
    health_status: TreeStatus
    notes: Optional[str]
    created_at: datetime
```

3. **Implement Business Logic** (`src/xr_forests/core/services/tree_service.py`)

```python
class TreeService:
    async def create_health_assessment(
        self, 
        assessment_data: TreeHealthAssessmentCreate
    ) -> TreeHealthAssessmentResponse:
        # Validation and business logic
        assessment = TreeHealthAssessment(**assessment_data.dict())
        # Save to database
        # Return response schema
```

4. **Create API Router** (`src/xr_forests/api/routers/tree.py`)

```python
@router.post("/{tree_id}/health", response_model=TreeHealthAssessmentResponse)
async def create_health_assessment(
    tree_id: UUID,
    assessment: TreeHealthAssessmentCreate,
    service: TreeService = Depends(get_tree_service)
):
    return await service.create_health_assessment(assessment)
```

5. **Write Tests** (`tests/unit/test_tree_service.py`)

```python
async def test_create_health_assessment():
    service = TreeService()
    assessment_data = TreeHealthAssessmentCreate(
        tree_id=uuid.uuid4(),
        assessment_date=date.today(),
        health_status=TreeStatus.HEALTHY
    )
    result = await service.create_health_assessment(assessment_data)
    assert result.health_status == TreeStatus.HEALTHY
```

### Database Migrations

```bash
# Create migration after model changes
alembic revision --autogenerate -m "Add tree health assessments"

# Apply migration
alembic upgrade head

# Check current migration status
alembic current
```

### Testing Strategies

**Unit Tests**: Test individual components

```bash
# Run specific test files
pytest tests/unit/test_tree_service.py

# Run with coverage
pytest --cov=src/xr_forests tests/

# Generate coverage report
pytest --cov=src/xr_forests --cov-report=html tests/
open htmlcov/index.html
```

**Integration Tests**: Test API endpoints

```bash
# Run integration tests
pytest tests/integration/

# Test specific endpoints
pytest tests/integration/test_tree_endpoints.py -v
```

**API Testing**: Use the interactive docs

1. Open <http://localhost:8000/docs>
2. Test endpoints manually
3. Verify request/response formats
4. Check error handling

## 🐛 **Debugging and Development Tools**

### Local Development

**API Logs**

```bash
# View real-time API logs
docker-compose logs -f api

# Debug specific issues
docker-compose logs api | grep ERROR
```

**Database Access**

```bash
# Connect to database
docker exec -it xr_forests_db psql -U forests_user -d xr_forests_lab

# Common queries
SELECT * FROM locations LIMIT 5;
SELECT COUNT(*) FROM trees;
\dt  # List tables
\d+ trees  # Describe trees table
```

**Redis Debugging**

```bash
# Connect to Redis
docker exec -it xr_forests_redis redis-cli

# Monitor events
MONITOR

# Check cache keys
KEYS *
```

### Development Services

**Hot Reload**: API automatically reloads on code changes

**Interactive Debugging**: Add breakpoints with `pdb`

```python
import pdb; pdb.set_trace()  # Add this line for debugging
```

**Performance Profiling**

```bash
# Profile API endpoints
pip install py-spy
py-spy record -o profile.svg -d 30 -p $(pgrep python)
```

## 📊 **Code Quality and Standards**

### Code Formatting

```bash
# Format code
black src/ tests/

# Sort imports
isort src/ tests/

# Check formatting
black --check src/
isort --check-only src/
```

### Type Checking

```bash
# Run type checker
mypy src/

# Check specific files
mypy src/xr_forests/core/services/
```

### Linting

```bash
# Run flake8
flake8 src/ tests/

# Fix common issues
autopep8 --in-place --recursive src/
```

### Pre-commit Hooks

```bash
# Install pre-commit
pre-commit install

# Run all hooks manually
pre-commit run --all-files
```

## 🚀 **Advanced Development**

### Performance Optimization

**Database Query Optimization**

- Use `EXPLAIN ANALYZE` for slow queries
- Add appropriate indexes
- Optimize spatial queries with PostGIS

**API Performance**

- Use async/await properly
- Implement connection pooling
- Add response caching where appropriate

**Memory Management**

- Profile large point cloud processing
- Implement streaming for large files
- Monitor memory usage in containers

### Extension Points

**Adding New Data Processing**

1. Create service in `core/services/`
2. Define background tasks
3. Add Redis event handling
4. Implement API endpoints

**External System Integration**

1. Add configuration in `config/settings.py`
2. Create client classes
3. Implement error handling and retries
4. Add health checks

### Deployment Preparation

**Environment Configuration**

```bash
# Production settings
cp .env.example .env.production
# Edit production values

# Test with production-like settings
docker-compose -f docker-compose.prod.yml up
```

**Security Checklist**

- Review all environment variables
- Check CORS settings
- Validate input sanitization
- Test authentication (when implemented)
- Review file upload security

## 🤝 **Contributing Guidelines**

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/tree-health-assessment

# Make changes and commit
git add .
git commit -m "Add tree health assessment endpoints"

# Push and create pull request
git push origin feature/tree-health-assessment
```

### Pull Request Checklist

- [ ] Code follows project formatting standards
- [ ] All tests pass
- [ ] New features have tests
- [ ] Documentation updated
- [ ] API endpoints documented
- [ ] Database migrations included (if needed)

### Code Review Process

1. **Automated Checks**: CI runs tests and formatting checks
2. **Manual Review**: Team reviews code and design
3. **Integration Testing**: Test in development environment
4. **Documentation**: Update relevant documentation
5. **Merge**: Squash commits and merge to main

## 📚 **Development Resources**

### Key Documentation

- **[API Overview](../api/overview.md)** - Understanding the API design
- **[System Architecture](../architecture/system-architecture.md)** - System design details
- **[Database Design](../architecture/database-design.md)** - Schema and relationships

### External Resources

- **[FastAPI Documentation](https://fastapi.tiangolo.com/)** - API framework
- **[SQLAlchemy 2.0](https://docs.sqlalchemy.org/en/20/)** - ORM and database
- **[PostGIS](https://postgis.net/documentation/)** - Spatial database extensions
- **[Redis](https://redis.io/documentation)** - Caching and events

### Development Tools

| Tool | Purpose | Documentation |
|------|---------|---------------|
| **pytest** | Testing framework | [docs](https://pytest.org/) |
| **black** | Code formatting | [docs](https://black.readthedocs.io/) |
| **mypy** | Type checking | [docs](https://mypy.readthedocs.io/) |
| **alembic** | Database migrations | [docs](https://alembic.sqlalchemy.org/) |

---

**🛠️ Ready to develop!** You now have everything needed to contribute effectively to the XR Future Forests Lab.
