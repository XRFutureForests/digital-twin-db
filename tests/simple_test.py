"""Simple integration test for the new API structure."""


def test_health_endpoint_simple():
    """Test the health endpoint works with new structure."""
    from xr_forests.api.routers.health import router

    # Simulate a request to the health endpoint
    from xr_forests.api.routers.health import health_check
    import asyncio

    # Test the function directly
    result = asyncio.run(health_check())

    assert result["status"] == "healthy"
    assert result["service"] == "XR Future Forests Lab API"
    assert result["version"] == "1.0.0"

    print("✅ Health endpoint test passed!")


def test_application_import():
    """Test that the application can be imported successfully."""
    from xr_forests.api.main import create_app

    app = create_app()
    assert app.title == "XR Future Forests Lab API"
    assert len(app.routes) > 0

    print("✅ Application import test passed!")


def test_router_structure():
    """Test that the router structure is working."""
    from xr_forests.api.routers import health_router, locations_router

    # Check health router
    assert health_router.tags == ["health"]

    # Check locations router
    assert locations_router.prefix == "/api/locations"
    assert locations_router.tags == ["locations"]

    print("✅ Router structure test passed!")


if __name__ == "__main__":
    print("🧪 Running simple tests for restructured API...")
    print("=" * 50)

    tests = [
        test_application_import,
        test_health_endpoint_simple,
        test_router_structure,
    ]

    passed = 0
    total = len(tests)

    for test in tests:
        if test():
            passed += 1

    print("=" * 50)
    print(f"📊 Test Results: {passed}/{total} tests passed")

    if passed == total:
        print("🎉 All tests passed! The refactored structure is working correctly.")
    else:
        print("⚠️  Some tests failed. Review the structure.")
