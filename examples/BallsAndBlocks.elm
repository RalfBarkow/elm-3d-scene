module BallsAndBlocks exposing (main)

import Acceleration
import Angle
import Array exposing (Array)
import Block3d
import Browser
import Browser.Dom as Dom
import Browser.Events as Events
import Camera3d
import Color
import Common.Materials as Materials
import Direction3d
import Duration
import Frame3d
import Html exposing (Html)
import Html.Attributes
import Illuminance
import Length exposing (Length, inMeters, meters)
import Luminance
import Mass
import Palette.Tango as Tango
import Physics.Body as Body exposing (Body)
import Physics.Coordinates exposing (BodyCoordinates, WorldCoordinates)
import Physics.World as World exposing (World)
import Pixels exposing (pixels)
import Point3d
import Random
import Scene3d
import Scene3d.Chromaticity as Chromaticity
import Scene3d.Exposure as Exposure
import Scene3d.Material as Material exposing (Material)
import Scene3d.Mesh as Mesh exposing (Mesh)
import Sphere3d
import Task
import Viewpoint3d


type alias Model =
    { world : World (Scene3d.Entity BodyCoordinates)
    , screenWidth : Float
    , screenHeight : Float
    }


type Msg
    = Tick Float
    | Resize Float Float


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { world = initialWorld
      , screenWidth = 0
      , screenHeight = 0
      }
    , Task.perform
        (\{ viewport } -> Resize viewport.width viewport.height)
        Dom.getViewport
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            ( { model | world = World.simulate (Duration.seconds (1 / 60)) model.world }
            , Cmd.none
            )

        Resize width height ->
            ( { model | screenWidth = width, screenHeight = height }
            , Cmd.none
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Events.onResize (\w h -> Resize (toFloat w) (toFloat h))
        , Events.onAnimationFrameDelta Tick
        ]


view : Model -> Html Msg
view { world, screenWidth, screenHeight } =
    let
        camera =
            Camera3d.perspective
                { viewpoint =
                    Viewpoint3d.lookAt
                        { eyePoint = Point3d.meters 0 20 20
                        , focalPoint = Point3d.meters 0 0 0
                        , upDirection = Direction3d.positiveZ
                        }
                , clipDepth = meters 0.1
                , verticalFieldOfView = Angle.degrees 24
                }

        drawables =
            List.map getTransformedDrawable (World.getBodies world)

        sunlight =
            Scene3d.directionalLight Chromaticity.d65
                (Illuminance.lux 10000)
                (Direction3d.xyZ (Angle.degrees 45) (Angle.degrees -60))

        environmentalLighting =
            Scene3d.softLighting
                { upDirection = Direction3d.z
                , above = ( Luminance.nits 5000, Chromaticity.d65 )
                , below = ( Luminance.nits 0, Chromaticity.d65 )
                }
    in
    Html.div
        [ Html.Attributes.style "position" "absolute"
        , Html.Attributes.style "left" "0"
        , Html.Attributes.style "top" "0"
        ]
        [ Scene3d.toHtml
            { width = pixels screenWidth
            , height = pixels screenHeight
            , camera = camera
            , directLighting = Scene3d.oneLightSource sunlight { castsShadows = True }
            , environmentalLighting = environmentalLighting
            , exposure = Exposure.fromMaxLuminance (Luminance.nits 10000)
            , whiteBalance = Chromaticity.d65
            , backgroundColor = Scene3d.transparentBackground
            }
            drawables
        ]


initialWorld : World (Scene3d.Entity BodyCoordinates)
initialWorld =
    let
        moonGravity =
            Acceleration.metersPerSecondSquared 1.62
    in
    World.empty
        |> World.setGravity moonGravity Direction3d.negativeZ
        |> World.add floor
        |> addBoxes


materials : Array Material.ForMeshWithNormals
materials =
    Array.fromList
        [ Materials.aluminum
        , Materials.whitePlastic
        , Materials.copper
        , Material.nonmetal { baseColor = Tango.skyBlue1, roughness = 0.25 }
        , Materials.gold
        , Materials.whitePlastic
        , Material.nonmetal { baseColor = Tango.skyBlue2, roughness = 0.25 }
        ]


type alias Offsets =
    { x : Float
    , y : Float
    , z : Float
    }


offsetGenerator : Random.Generator Offsets
offsetGenerator =
    let
        magnitude =
            0.01
    in
    Random.map3 Offsets
        (Random.float -magnitude magnitude)
        (Random.float -magnitude magnitude)
        (Random.float -magnitude magnitude)


randomOffsets : Int -> Offsets
randomOffsets index =
    Random.step offsetGenerator (Random.initialSeed index)
        |> Tuple.first


addBoxes : World (Scene3d.Entity BodyCoordinates) -> World (Scene3d.Entity BodyCoordinates)
addBoxes world =
    let
        xySize =
            4

        zSize =
            5

        xyDimensions =
            List.map toFloat (List.range 0 (xySize - 1))

        zDimensions =
            List.map toFloat (List.range 0 (zSize - 1))

        distance =
            1
    in
    List.foldl
        (\x world1 ->
            List.foldl
                (\y world2 ->
                    List.foldl
                        (\z ->
                            let
                                index =
                                    round (z * xySize * xySize + y * xySize + x)

                                material =
                                    Array.get (index |> modBy (Array.length materials)) materials
                                        |> Maybe.withDefault Materials.aluminum

                                body =
                                    if (index |> modBy 3) == 0 then
                                        box material

                                    else
                                        sphere material

                                offsets =
                                    randomOffsets index
                            in
                            body
                                |> Body.moveTo
                                    (Point3d.meters
                                        ((x - (xySize - 1) / 2) * distance + offsets.x)
                                        ((y - (xySize - 1) / 2) * distance + offsets.y)
                                        ((z + (2 * zSize + 1) / 2) * distance + offsets.z)
                                    )
                                |> World.add
                        )
                        world2
                        zDimensions
                )
                world1
                xyDimensions
        )
        world
        xyDimensions


floorRadius : Length
floorRadius =
    Length.meters 30


floor : Body (Scene3d.Entity BodyCoordinates)
floor =
    let
        shape =
            Sphere3d.atOrigin floorRadius
    in
    Scene3d.sphere shape Materials.aluminum { castsShadow = False }
        |> Body.sphere shape
        |> Body.moveTo
            (Point3d.meters
                0
                0
                -(Length.inMeters floorRadius)
            )


boxSize : Length
boxSize =
    Length.meters 0.9


box : Material.ForMeshWithNormals -> Body (Scene3d.Entity BodyCoordinates)
box material =
    let
        shape =
            Block3d.centeredOn Frame3d.atOrigin
                ( boxSize, boxSize, boxSize )
    in
    Scene3d.block shape material { castsShadow = True }
        |> Body.block shape
        |> Body.setBehavior (Body.dynamic (Mass.kilograms 5))


sphereRadius : Length
sphereRadius =
    Length.meters 0.45


sphere : Material.ForMeshWithNormals -> Body (Scene3d.Entity BodyCoordinates)
sphere material =
    let
        shape =
            Sphere3d.atOrigin sphereRadius
    in
    Scene3d.sphere shape material { castsShadow = True }
        |> Body.sphere shape
        |> Body.setBehavior (Body.dynamic (Mass.kilograms 2.5))


getTransformedDrawable : Body (Scene3d.Entity BodyCoordinates) -> Scene3d.Entity WorldCoordinates
getTransformedDrawable body =
    Scene3d.placeIn (Body.getFrame3d body) (Body.getData body)
