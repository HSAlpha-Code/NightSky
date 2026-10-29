from rest_framework import serializers


class LandmarksQuerySerializer(serializers.Serializer):
    ra = serializers.FloatField(min_value=-360, max_value=720)
    dec = serializers.FloatField(min_value=-90, max_value=90)
    fov = serializers.FloatField(min_value=0.001, max_value=120)
    rotation = serializers.FloatField(required=False, default=0.0)
    aspect = serializers.FloatField(required=False, default=4 / 3, min_value=0.2, max_value=5)
    limit = serializers.IntegerField(required=False, min_value=1, max_value=100)


class LandmarkDetailQuerySerializer(serializers.Serializer):
    id = serializers.CharField(max_length=64)
    provider = serializers.CharField(required=False, allow_blank=True, default="")
    # auto = best available (JWST, then Hubble, then survey); or force one point of view.
    view = serializers.ChoiceField(choices=["auto", "jwst", "hst", "survey"], required=False,
                                   default="auto")
