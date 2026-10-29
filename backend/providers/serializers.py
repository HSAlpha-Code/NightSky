from rest_framework import serializers


class SkyImageRequestSerializer(serializers.Serializer):
    ra = serializers.FloatField(min_value=-360, max_value=720)
    dec = serializers.FloatField(min_value=-90, max_value=90)
    fov = serializers.FloatField(min_value=0.001, max_value=120)
    rotation = serializers.FloatField(required=False, default=0.0)
    provider = serializers.CharField(required=False, allow_blank=True, default="")
    width = serializers.IntegerField(required=False, default=1200, min_value=64, max_value=3000)
    height = serializers.IntegerField(required=False, default=1600, min_value=64, max_value=3000)


class ProviderSerializer(serializers.Serializer):
    key = serializers.CharField()
    name = serializers.CharField()
    description = serializers.CharField()
    wavelength = serializers.CharField()
    coverage = serializers.CharField()
    all_sky = serializers.BooleanField()
    service = serializers.CharField()
    credit = serializers.CharField()
